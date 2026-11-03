# Infisical: secrets for agents

Infisical stores runtime secrets that agents (Hermes, T3/Claude) need: model
provider keys, bot tokens, read-only infrastructure API tokens. GitOps
manifests keep using SOPS + age; Infisical does not replace that flow.

## Layout

| Piece | Where |
|---|---|
| App | `infisical` container on services-01, `infisical/infisical:v0.167.5`, host port 8085 |
| Database | `infisical` DB and role on postgres-01 (10.10.30.100) |
| Queue/cache | private `infisical-valkey` (noeviction, not published). The shared valkey runs `allkeys-lru`, which would evict BullMQ jobs. |
| URL | `https://secrets.app.hapa.dev` via local edge → k3s Traefik → `shared-services/infisical` → 10.10.30.101:8085. LAN/WireGuard only; not published publicly. |
| Bootstrap secrets | `INFISICAL_ENCRYPTION_KEY`, `INFISICAL_AUTH_SECRET`, `INFISICAL_DB_PASSWORD` in `/opt/homelab/services/.env` on services-01. Recovery copy: `~/.config/homelab/infisical.env` on the VS Code VM. |

**`INFISICAL_ENCRYPTION_KEY` is unrecoverable.** Without it, a database backup
cannot be decrypted. Keep a copy in an offline password manager in addition to
the file above.

## Deploy / upgrade

```bash
scp infrastructure/services/docker-compose.yaml ubuntu@10.10.30.101:/opt/homelab/services/
ssh ubuntu@10.10.30.101 'cd /opt/homelab/services && sudo docker compose up -d infisical-valkey infisical'
curl -fsS http://10.10.30.101:8085/api/status
```

To upgrade, bump the pinned image tag; migrations run on startup. Take a
`pg_dump infisical` on postgres-01 first.

## Agent access model

One project per agent, so an identity can never read another agent's secrets:

| Project | Machine identity | Role | Trusted IPs |
|---|---|---|---|
| `hermes` | `hermes` | Viewer | 10.10.30.229/32 (LXC 108) |
| `t3-agents` | `t3-vscode` | Viewer | 10.10.30.70/32 (VS Code VM) |

Universal Auth settings per identity: access token TTL 1h, max TTL 24h, the
client secret and access token both restricted to the trusted IP. Agents only
read secrets; writes happen as a human through the UI.

### Create an identity

1. Organization → Access Control → Identities → Create (`hermes`, org role
   *No Access*).
2. Auth: Universal Auth, apply the TTL and trusted IP settings above, then
   create a client secret.
3. Project → Access Control → Machine Identities → add the identity as Viewer.
4. Write the identity file on the agent host (mode 600, owned by the user
   that runs the agent):

   ```
   INFISICAL_CLIENT_ID=...
   INFISICAL_CLIENT_SECRET=...
   INFISICAL_PROJECT_ID=...
   ```

### T3 / Claude on the VS Code VM

Identity file: `~/.config/homelab/infisical-agent.env`. Run commands with
secrets injected as environment variables:

```bash
scripts/infisical-run.sh -- printenv | cut -d= -f1      # list names only
scripts/infisical-run.sh --path /aws -- aws sts get-caller-identity
```

Agents should reference secrets by variable name and never echo values.

### Hermes (LXC 108)

Install the CLI as root, then put the identity file at
`/home/hermes/.config/homelab/infisical-agent.env` (owner `hermes`, mode 600)
and copy `scripts/infisical-run.sh` to `/home/hermes/.local/bin/`.

Check the real unit and command first (`systemctl cat hermes-gateway`), then start the gateway through the wrapper so keys live only in the process
environment, not in `~/.hermes/.env`:

```ini
# systemctl edit hermes-gateway
[Service]
ExecStart=
ExecStart=/home/hermes/.local/bin/infisical-run.sh -- /home/hermes/.local/bin/hermes gateway
```

Once the gateway reads keys from Infisical, delete them from
`~/.hermes/.env`.

## Rotation and revocation

- Rotate a value in the UI; agents pick it up on next process start.
- Revoke an agent: delete its client secret (Universal Auth tab). Its current
  access token expires within the 1h TTL.
- Audit: Project → Audit Logs shows every secret read by identity.
