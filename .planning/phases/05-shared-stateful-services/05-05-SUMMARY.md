---
phase: 05-shared-stateful-services
plan: 05
status: partial
one_liner: "Deployed the Phase 05 stack for the first time; fixed 12 latent bugs; 6/7 SERV requirements live and verified; SERV-07 restore proven into a disposable instance, blocked only on one NAS grant for the off-host write"
verified: 2026-07-08
requirements_complete: [SERV-01, SERV-02, SERV-03, SERV-04, SERV-05, SERV-06]
requirements_blocked: [SERV-07]
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
- **k3s discovery (SERV-05, SERV-06)** — Argo manages namespace + 5 selectorless
  Services + 5 EndpointSlices (Synced/Healthy). Live test passes: in-cluster workloads
  reach postgres/valkey/nats/debezium via `*.shared-services.svc.cluster.local` and
  Zitadel via its EndpointSlice (10.10.30.236) + OIDC discovery. Required un-excluding
  `EndpointSlice` in `argocd-cm` (see fix #12) and publishing Debezium's 8080.

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
12. `argocd-cm`: un-exclude `discovery.k8s.io/EndpointSlice` (Phase 3 default excluded it, so Argo silently dropped all 5 slices and the selectorless Services had no backends) + publish Debezium 8080 to match its EndpointSlice. **Decision taken by user:** un-exclude in argocd-cm.

## Resolved during this plan (user decisions)

- **SERV-05 / SERV-06 (k8s discovery):** root cause was Argo's `argocd-cm` excluding
  `EndpointSlice`. Fixed by `infrastructure/kubernetes/argocd/argocd-cm-patch.yaml`
  (merge-patched live + wired into `install_argocd`) and restarting the
  application-controller. All 5 EndpointSlices now Argo-managed; live discovery test
  passes. Debezium 8080 published to match its advertised endpoint.

## SERV-07 — restore proven; only the NAS storage hop remains (one operator action)

**Design revised (2026-07-08b).** The Proxmox-host approach the operator picked is
**not executable**: root ssh to `10.10.30.30` is denied by key *and* password, and the
PVE API exposes no host shell — there is no shell path onto that host. The unprivileged
LXC also cannot mount NFS (the `nfs` feature flag is root@pam-only). The one host that
can *both* reach the LXC *and* the NAS is the **operator workstation** (`10.10.30.70`),
so backup is now **workstation-mediated**:

- **backup:** `postgres LXC --ssh--> workstation --nfs--> NAS`
- **restore-test:** `NAS --nfs--> workstation --ssh--> disposable postgres:17 container on services-01`

Verified live this session (NAS bypassed by streaming straight into the scratch
container): a real `pg_dumpall` from the LXC **restores cleanly into a disposable,
isolated postgres:17 instance** — `debezium` role reconstructed (replication+login) and
`dbz_publication` recreated — then torn down. This is the risky part of SERV-07 and it
**passes**. Also fixed a latent correctness bug in the old restore path: it fed a full
`pg_dumpall` (global `DROP/CREATE ROLE`, `\connect`) into a scratch DB **on the live
server**, which would mutate production — restore now targets a throwaway container.

**Only remaining action (NAS, not automatable — no NAS creds on hand):** grant the
workstation `10.10.30.70` **read/write** NFS access to `10.10.40.2:/volume1/homelab-backups`.
The folder exists but the export currently denies `10.10.30.70` (`access denied by
server`; the only live export rule is `/volume1/surveillance → 10.10.30.30`). Once
granted: `scripts/postgres-platform.sh backup && scripts/postgres-platform.sh restore-test`.

## Security note (tech debt)

The `debezium` DB password is the hardcoded literal `debezium` (in
`postgres-platform.sh` and the services `.env`). Fine to bring the stack up; should be
rotated to a SOPS-managed secret before real data flows. See [[05-RESEARCH]] secrets note.

## Commits

- `fix(05): correct Postgres LXC provider schema and preflight API`
- `fix(05): make shared services actually deploy and run`
- `fix(05): adopt shared LXC template, drop root-only NFS feature, pin providers`
- gitops-homelab `bcd8b42`: published `apps/shared-services` for Argo discovery
