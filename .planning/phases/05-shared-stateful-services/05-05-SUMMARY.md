---
phase: 05-shared-stateful-services
plan: 05
status: partial
one_liner: "Actually deployed the Phase 05 stack for the first time; fixed 11 latent bugs; 4/7 SERV requirements now live and verified, 3 blocked on cross-phase decisions"
verified: 2026-07-08
requirements_complete: [SERV-01, SERV-02, SERV-03, SERV-04]
requirements_blocked: [SERV-05, SERV-06, SERV-07]
---

# Plan 05-05 Execution Summary

/ Deployment of the shared stateful services. Plans 01–04 produced IaC, scripts,
and manifests but never provisioned anything; this plan ran them for the first
time against real Proxmox/k3s and fixed every latent bug that surfaced.

## What is now live and verified

- **postgres-01** — unprivileged LXC 120 at `10.10.30.100`. PostgreSQL 17 with
  `wal_level=logical`, `max_replication_slots=4`, `max_wal_senders=4`,
  `max_slot_wal_keep_size=4GB`, `shared_buffers=1024MB`, `listen_addresses='*'`,
  `pg_hba` allowing `10.10.30.0/24`. `debezium` role (REPLICATION+LOGIN) and
  `dbz_publication` created. Reachable on 5432 from the LAN. **(SERV-01, SERV-04 WAL side)**
- **services-01** — cloud-init VM 121 at `10.10.30.101`, Docker 29.6.1 + Compose v5.
  - **Valkey** healthy, 1536M limit, `PING→PONG` from LAN. **(SERV-02)**
  - **NATS JetStream** healthy, `max_mem_store=256Mb` / `max_file_store=4Gb` confirmed. **(SERV-03)**
  - **Debezium** healthy, connected to Postgres, replication slot `debezium_homelab`
    active (`wal_status=reserved`), heartbeats flowing to JetStream (`DebeziumStream`
    accumulating messages). Full Postgres→Debezium→NATS CDC pipeline proven. **(SERV-04)**
- **k3s discovery Services** — Argo synced `apps/shared-services` (Synced/Healthy);
  namespace + 5 selectorless Services (postgres, valkey, nats, debezium, zitadel) exist.

## Bugs fixed (all latent — phase was only `fmt`-checked, never deployed)

1. `postgres/main.tf`: `proxmox_virtual_environment_container` has no top-level `name` arg.
2. `postgres/main.tf`: `features.nfs` invalid → the whole NFS-in-LXC backup approach is unviable (see SERV-07).
3. `postgres-platform.sh`: preflight `/cluster/resources?type=lxc` → HTTP 400; must be `type=vm`.
4. `postgres/main.tf` & `services/main.tf`: `overwrite_unmanaged=true` so `apply` adopts the pre-existing shared Ubuntu image instead of erroring.
5. `postgres-platform.sh`: SSH as `root` (standard LXC template is root-only, no `ubuntu` user).
6. `services-platform.sh` deploy: `sudo mkdir`+`chown /opt/homelab` so the unprivileged `scp` works.
7. `docker-compose.yaml`: add `env_file: .env` to debezium so `DEBEZIUM_DB_PASSWORD` reaches it.
8. `docker-compose.yaml`: mount `application.properties` at `/debezium/config` (not `/debezium/conf`).
9. `application.properties` + `postgres-platform.sh`: pre-create `dbz_publication` as superuser and set `publication.autocreate.mode=disabled` (least-privilege role can't `CREATE PUBLICATION FOR ALL TABLES`).
10. `application.properties`: widen sink subjects to `homelab.>` and `__debezium-heartbeat.>` (narrow filter → JetStream `503 No Responders`).
11. `services-platform.sh` validate: count running via `{{.State}}` template (Compose v5 JSON has no space, old grep always read 0).

## Blocked — need decisions / infra changes (not code I can fix alone)

- **SERV-05 / SERV-06 (k8s discovery):** Argo CD's `argocd-cm` `resource.exclusions`
  (Phase 3 platform default) excludes `Endpoints` **and** `EndpointSlice`. Argo therefore
  silently drops all 5 EndpointSlices, so the selectorless Services have no backends.
  Proven root cause: manually applying `endpointslice-postgres` immediately gave the
  Service `Endpoints: 10.10.30.100:5432`. **Decision needed:** un-exclude `EndpointSlice`
  in argocd-cm (simple, low cost at homelab scale, makes the committed design work) vs.
  create the EndpointSlices out-of-band. This modifies a Phase 3 platform artifact.
- **SERV-07 (backup/restore):** two blockers. (a) The assumed NFS export
  `10.10.40.2:/volume1/backup/postgres` does not exist — the NAS only exports
  `/volume1/surveillance` to the Proxmox host. (b) The scripted backup mounts NFS
  *inside* the unprivileged LXC, which is blocked (feature flags need `root@pam`; the
  API token got HTTP 403, and NFS-in-unprivileged-LXC is unreliable). **Decision needed:**
  create a backup export on the NAS + choose a backup host/design (e.g. stream
  `pg_dumpall` over SSH to an NFS-mounted operator/Proxmox host).

## Security note (tech debt)

The `debezium` DB password is the hardcoded literal `debezium` (in
`postgres-platform.sh` and the services `.env`). Fine to bring the stack up; should be
rotated to a SOPS-managed secret before real data flows. See [[05-RESEARCH]] secrets note.

## Commits

- `fix(05): correct Postgres LXC provider schema and preflight API`
- `fix(05): make shared services actually deploy and run`
- `fix(05): adopt shared LXC template, drop root-only NFS feature, pin providers`
- gitops-homelab `bcd8b42`: published `apps/shared-services` for Argo discovery
