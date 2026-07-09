---
phase: 05-shared-stateful-services
date: 2026-07-07
status: complete
---

# Phase 5 Research: Shared Stateful Services

## Overview

This research investigates how to implement Phase 5, which provisions durable LAN services outside k3s and makes them consumable through stable Kubernetes service names. The phase covers seven requirements:

- **SERV-01**: PostgreSQL in a dedicated LXC (postgres-01, LXC 120)
- **SERV-02**: Valkey in the shared-services Compose VM (services-01, VM 121)
- **SERV-03**: NATS + JetStream in the same Compose VM with bounded storage
- **SERV-04**: Debezium Server in the same Compose VM with WAL growth control
- **SERV-05**: Kubernetes selectorless Services + EndpointSlices for stable names
- **SERV-06**: Integration with existing Zitadel at zitadel.kayage.co
- **SERV-07**: Off-host PostgreSQL backup and verified restore via NFS

The research examines existing codebase patterns from Phases 2–4 and identifies concrete approaches for each requirement.

## Findings

### 1. Codebase Patterns and Conventions (Established in Prior Phases)

#### OpenTofu Structure

The existing k3s VM is provisioned via `infrastructure/opentofu/k3s/` using the `bpg/proxmox` provider v0.111.0 with OpenTofu 1.12.1. Key patterns:

- **State encryption**: PBKDF2 + AES-GCM with passphrase from `TF_VAR_state_passphrase` (generated and stored in `.local/state-passphrase`)
- **Provider authentication**: SSH key + API token from external env file (`/home/tonny/.config/homelab/proxmox.env`)
- **Cloud-init**: Template file (`.tftpl`) renders hostname, k3s version, SSH key
- **Locals block**: All identity/allocation values (VMID, IP, name, versions) are in locals, matching `infrastructure/inventory.json`
- **Tags**: `["opentofu", "k3s", "disposable"]`
- **VM resource structure**: `proxmox_virtual_environment_vm` with `cpu`, `memory`, `disk`, `initialization`, `network_device`, `startup` blocks

Phase 5 should create two new OpenTofu roots:
- `infrastructure/opentofu/postgres/` for LXC 120
- `infrastructure/opentofu/services/` for VM 121

#### GitOps Structure

- Apps live in `gitops/apps/<name>/` with `kustomization.yaml` + resources
- Platform-level resources live in `gitops/platform/`
- SOPS config at `gitops/.sops.yaml` uses age key `age1vqhscpppn2trashhqzg2c5jp0zrhmj6e26pum9rk8s4mf07eqchqacgyyq`
- Encrypted secrets follow `*.enc.yaml` naming; the SOPS CMP plugin decrypts during Argo CD reconciliation
- The ApplicationSet auto-discovers `apps/*` directories and creates per-app namespaces

The shared-services discovery objects should go in a new `gitops/apps/shared-services/` directory, since the ApplicationSet creates namespaces from `apps/*` directories.

#### Scripts and Tests

- Scripts in `scripts/` follow the pattern: `load_environment()`, `preflight()`, subcommands via `case` dispatch
- Tests in `tests/` use `static` (offline) and `live` (cluster-connected) modes
- Proof artifacts stored as `.local/phase-NN-*`
- Credentials loaded from `/home/tonny/.config/homelab/*.env`

#### Inventory Contract

`infrastructure/inventory.json` is the canonical source for all guest identities:

| Guest | Kind | VMID | IP | DNS | vCPU | RAM | Disk | Startup |
|-------|------|------|----|-----|------|-----|------|---------|
| postgres-01 | LXC | 120 | 10.10.30.100 | postgres.app.kayage.co | 2 | 4096 MiB | 64 GiB | order 10, delay 30s |
| services-01 | VM | 121 | 10.10.30.101 | services.app.kayage.co | 4 | 8192 MiB | 64 GiB | order 20, delay 30s |
| zitadel-existing | LXC | 112 | 10.10.30.236 | zitadel.kayage.co | 1 | 1024 MiB | 8 GiB | order 15 |

### 2. SERV-01: PostgreSQL in Dedicated LXC

#### OpenTofu LXC Resource

The `bpg/proxmox` provider has `proxmox_virtual_environment_container` for LXC. Key differences from VM:

```hcl
resource "proxmox_virtual_environment_container" "postgres" {
  node_name    = "proxmox"
  vm_id        = 120
  description  = "Dedicated PostgreSQL server managed by OpenTofu"
  tags         = ["opentofu", "postgres", "durable"]
  unprivileged = true
  start_on_boot = true

  startup {
    order      = "10"
    up_delay   = "30"
    down_delay = "30"
  }
  cpu { cores = 2 }
  memory { dedicated = 4096 }

  disk {
    datastore_id = "local-lvm"
    size         = 64
  }
  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }
  initialization {
    hostname = "postgres-01"
    ip_config {
      ipv4 { address = "10.10.30.100/24"; gateway = "10.10.30.1" }
    }
    user_account {
      keys = [var.ssh_public_key]
    }
  }
  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.ubuntu_lxc.id
    type             = "ubuntu"
  }
}
```

LXC template: Use `proxmox_virtual_environment_download_file` with `content_type = "vztmpl"` for Ubuntu 24.04 container template.

#### PostgreSQL Installation and Configuration

- **Version**: PostgreSQL 17 (latest stable as of 2026). Install from the PostgreSQL APT repository for version pinning.
- **`postgresql.conf` tuning** for 2 vCPU / 4 GB:
  - `shared_buffers = 1024MB` (25% of 4 GB)
  - `effective_cache_size = 3072MB` (75% of 4 GB)
  - `work_mem = 16MB`
  - `maintenance_work_mem = 256MB`
  - `wal_level = logical` (required for Debezium CDC)
  - `max_replication_slots = 4` (for Debezium + headroom)
  - `max_wal_senders = 4`
  - `max_slot_wal_keep_size = 4GB` (bound WAL growth per slot)
  - `listen_addresses = '10.10.30.100'` (bind only to LAN interface)
- **`pg_hba.conf`**:
  ```
  # Local unix socket
  local   all   postgres                peer
  local   all   all                     peer
  # k3s and services-01 subnet access
  host    all   all   10.10.30.0/24     scram-sha-256
  ```
- **Roles and databases**: Create a `debezium` role with `REPLICATION` and `LOGIN` privileges. Application databases will be created in Phase 6 (scaffolding), but a template pattern should be established.
- **Publication for CDC**: Create a `FOR ALL TABLES` publication or a named publication for Debezium. This must exist before Debezium can stream changes.

#### Configuration Automation

Per the architecture boundaries, `config-automation` owns post-provisioning configuration. Options:
1. **SSH + shell script** (consistent with k3s-platform.sh pattern): Run PostgreSQL setup commands via SSH after OpenTofu creates the LXC. This is the simplest approach matching existing patterns.
2. **Cloud-init in LXC**: The `bpg/proxmox` container resource does not support cloud-init user-data the same way VMs do. LXC uses the `initialization` block for hostname, network, and user account only.

**Recommended approach**: A `scripts/postgres-platform.sh` script that:
1. Provisions the LXC via OpenTofu
2. SSHs in to install PostgreSQL from APT
3. Deploys configuration files
4. Creates roles and databases
5. Validates connectivity

### 3. SERV-02: Valkey in Compose VM

#### VM Provisioning

services-01 (VM 121) follows the same `proxmox_virtual_environment_vm` pattern as k3s-01 but with different allocations (4 vCPU, 8192 MiB, 64 GiB, startup order 20). Cloud-init should install Docker and Docker Compose.

#### Valkey Configuration

- **Image**: `valkey/valkey:8-alpine` (latest 8.x stable)
- **Full Redis compatibility**: Valkey is a drop-in replacement for Redis OSS 7.2. All existing Redis client libraries (ioredis, redis-py, etc.) work unchanged.
- **Key configuration**:
  ```yaml
  services:
    valkey:
      image: valkey/valkey:8-alpine
      command: >
        valkey-server
        --maxmemory 1gb
        --maxmemory-policy allkeys-lru
        --appendonly yes
        --save 900 1
        --save 300 10
      ports:
        - "6379:6379"
      volumes:
        - valkey-data:/data
      deploy:
        resources:
          limits:
            memory: 1536M
            cpus: "1.0"
      healthcheck:
        test: ["CMD", "valkey-cli", "ping"]
        interval: 10s
        timeout: 3s
        retries: 3
  ```
- **Memory policy**: `allkeys-lru` is appropriate for caching. The `maxmemory` should be set below the container memory limit to leave room for Valkey overhead.
- **Persistence**: AOF (`--appendonly yes`) + periodic RDB snapshots. Data volume mapped to named Docker volume.
- **T3 app connection**: T3 apps use `@upstash/redis` or `ioredis` client; connection string is `redis://valkey.shared-services.svc.cluster.local:6379` (via the k8s service).

### 4. SERV-03: NATS + JetStream in Compose VM

#### Configuration

```yaml
services:
  nats:
    image: nats:2-alpine
    command: ["-c", "/etc/nats/nats.conf"]
    ports:
      - "4222:4222"   # Client
      - "8222:8222"   # HTTP monitoring
    volumes:
      - ./nats.conf:/etc/nats/nats.conf:ro
      - nats-data:/data
    deploy:
      resources:
        limits:
          memory: 2048M
          cpus: "1.5"
    healthcheck:
      test: ["CMD", "nats-server", "--signal", "ldm=http://localhost:8222"]
      interval: 10s
      timeout: 3s
      retries: 3
```

**nats.conf**:
```
server_name: homelab-nats
listen: 0.0.0.0:4222
http_port: 8222

jetstream {
    store_dir: /data/jetstream
    max_mem_store: 256Mb
    max_file_store: 4Gb
}
```

- **Bounded storage**: `max_file_store: 4Gb` prevents JetStream from consuming all disk. `max_mem_store: 256Mb` for in-memory streams.
- **Health check**: The NATS server built-in health endpoint at port 8222 or the `nats-server --signal` approach. A simpler alternative for the health check: `wget --spider http://localhost:8222/healthz`.
- **Stream-level limits**: When creating streams, apply `max_bytes` per stream. Debezium-created streams should use `WorkQueue` or `Limits` retention.
- **Monitoring**: HTTP monitoring at `:8222` exposes `/jsz` for JetStream stats and `/varz` for general server stats.

### 5. SERV-04: Debezium Server in Compose VM

#### Architecture

Debezium Server runs standalone (not Kafka Connect). It reads PostgreSQL WAL via logical replication and publishes change events to NATS JetStream subjects.

#### Docker Compose Service

```yaml
services:
  debezium:
    image: quay.io/debezium/server:3.0
    volumes:
      - ./debezium/application.properties:/debezium/conf/application.properties:ro
      - debezium-data:/debezium/data
    deploy:
      resources:
        limits:
          memory: 1024M
          cpus: "1.0"
    depends_on:
      nats:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8080/q/health || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 30s
```

#### application.properties

```properties
# Sink: NATS JetStream
debezium.sink.type=nats-jetstream
debezium.sink.nats-jetstream.url=nats://nats:4222
debezium.sink.nats-jetstream.create-stream=true
debezium.sink.nats-jetstream.subjects=homelab,homelab.*.*.*

# Source: PostgreSQL
debezium.source.connector.class=io.debezium.connector.postgresql.PostgresConnector
debezium.source.offset.storage.file.filename=/debezium/data/offsets.dat
debezium.source.offset.flush.interval.ms=60000
debezium.source.database.hostname=10.10.30.100
debezium.source.database.port=5432
debezium.source.database.user=debezium
debezium.source.database.password=${DEBEZIUM_DB_PASSWORD}
debezium.source.database.dbname=postgres
debezium.source.topic.prefix=homelab
debezium.source.plugin.name=pgoutput
debezium.source.slot.name=debezium_homelab

# Heartbeat to advance LSN even during idle periods
debezium.source.heartbeat.interval.ms=30000

# Transforms (optional, for routing)
debezium.transforms=unwrap
debezium.transforms.unwrap.type=io.debezium.transforms.ExtractNewRecordState
```

#### WAL Growth Control

Two layers of defense:

1. **PostgreSQL `max_slot_wal_keep_size = 4GB`**: If the Debezium slot falls behind by more than 4 GB of WAL, PostgreSQL invalidates the slot and recycles WAL segments. This prevents runaway disk usage.
2. **Debezium `heartbeat.interval.ms = 30000`**: Sends heartbeat events every 30 seconds, ensuring the replication slot's LSN advances even when no application table changes occur. This prevents WAL accumulation during idle periods.

**Monitoring slot lag**:
```sql
SELECT slot_name, active,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal
FROM pg_replication_slots;
```

**Important**: If the slot is invalidated by `max_slot_wal_keep_size`, Debezium must be re-snapshotted. The `debezium.source.snapshot.mode` property controls this behavior.

### 6. SERV-05: Kubernetes Selectorless Services + EndpointSlices

#### Approach

Create selectorless Services paired with EndpointSlices in a `shared-services` namespace. These are GitOps-managed YAML in `gitops/apps/shared-services/`.

#### Example: PostgreSQL

```yaml
# service-postgres.yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: shared-services
spec:
  ports:
    - name: tcp-postgres
      port: 5432
      targetPort: 5432
      protocol: TCP
---
# endpointslice-postgres.yaml
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: postgres-1
  namespace: shared-services
  labels:
    kubernetes.io/service-name: postgres
    endpointslice.kubernetes.io/managed-by: homelab-gitops
addressType: IPv4
ports:
  - name: tcp-postgres
    protocol: TCP
    port: 5432
endpoints:
  - addresses:
      - "10.10.30.100"
    conditions:
      ready: true
```

#### Services to Create

| Service Name | Target IP | Port(s) | k8s DNS Name |
|-------------|-----------|---------|--------------|
| postgres | 10.10.30.100 | 5432 | postgres.shared-services.svc.cluster.local |
| valkey | 10.10.30.101 | 6379 | valkey.shared-services.svc.cluster.local |
| nats | 10.10.30.101 | 4222, 8222 | nats.shared-services.svc.cluster.local |
| debezium | 10.10.30.101 | 8080 | debezium.shared-services.svc.cluster.local |
| zitadel | 10.10.30.236 | 443, 8080 | zitadel.shared-services.svc.cluster.local |

#### Critical Details

- **`kubernetes.io/service-name` label is required** on EndpointSlice for the Service to discover it
- **`endpointslice.kubernetes.io/managed-by`** should be set to something other than `endpointslice-controller.k8s.io` (e.g., `homelab-gitops`) so the built-in controller doesn't try to manage/reconcile it
- **No selector** on the Service means Kubernetes won't auto-create Endpoints
- These live in `gitops/apps/shared-services/` so the existing ApplicationSet discovers them automatically
- The ApplicationSet creates the `shared-services` namespace via `CreateNamespace=true`

#### Kustomization

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - service-postgres.yaml
  - endpointslice-postgres.yaml
  - service-valkey.yaml
  - endpointslice-valkey.yaml
  - service-nats.yaml
  - endpointslice-nats.yaml
  - service-debezium.yaml
  - endpointslice-debezium.yaml
  - service-zitadel.yaml
  - endpointslice-zitadel.yaml
```

#### Connection Test Workload

A lightweight Pod/Job that verifies connectivity to all services:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: shared-services-connectivity-test
  namespace: shared-services
spec:
  template:
    spec:
      containers:
        - name: test
          image: alpine:3.20
          command: ["/bin/sh", "-c"]
          args:
            - |
              apk add --no-cache postgresql-client redis nats-client curl
              # Test postgres
              pg_isready -h postgres.shared-services.svc.cluster.local -p 5432
              # Test valkey
              redis-cli -h valkey.shared-services.svc.cluster.local ping
              # Test NATS
              nats server check -s nats://nats.shared-services.svc.cluster.local:4222
              # Test Zitadel
              curl -fsS https://zitadel.kayage.co/.well-known/openid-configuration
      restartPolicy: Never
```

### 7. SERV-06: Zitadel Integration

#### Current State

Zitadel is running at:
- **IP**: 10.10.30.236 (LXC 112)
- **TLS hostname**: `zitadel.kayage.co` (valid TLS)
- **Ownership**: `manual-existing` — Phase 5 does NOT manage its lifecycle

#### Integration Approach

1. **Selectorless Service + EndpointSlice** (as above) for `zitadel.shared-services.svc.cluster.local`
2. **For Zitadel with TLS**: Since Zitadel has valid TLS at `zitadel.kayage.co`, applications should connect using the FQDN directly for OIDC flows (the browser must resolve the OIDC issuer). The selectorless Service is useful for backend-to-backend calls.
3. **OIDC client configuration**: Zitadel provides standard OIDC discovery at `https://zitadel.kayage.co/.well-known/openid-configuration`. Applications configure:
   - `ZITADEL_ISSUER=https://zitadel.kayage.co`
   - `ZITADEL_CLIENT_ID=<app-specific-client-id>`
   - `ZITADEL_CLIENT_SECRET=<encrypted-via-sops>`

#### Important Consideration

The OIDC issuer URL that applications use must match what the browser sees. Since Zitadel's issuer is `https://zitadel.kayage.co`, applications should use that URL (not the cluster-internal name) as the issuer. The cluster-internal service is for health checks and non-browser flows only.

### 8. SERV-07: PostgreSQL Backup via NFS

#### NFS Setup in LXC

Mount the NAS NFS export inside the postgres-01 LXC:

```bash
# On the LXC (or via configuration automation)
apt install nfs-common
mkdir -p /mnt/backup

# /etc/fstab entry
10.10.40.2:/backup/postgres  /mnt/backup  nfs  hard,nfsvers=4,noatime  0  0
```

For unprivileged LXC, the NFS mount should be configured as a bind mount from the Proxmox host:
1. Mount NFS on the Proxmox host: `mount -t nfs 10.10.40.2:/backup/postgres /mnt/pve/postgres-backup`
2. Add bind mount to LXC config: `mp0: /mnt/pve/postgres-backup,mp=/mnt/backup`

This avoids permission issues with NFS inside unprivileged containers.

#### Backup Script

```bash
#!/usr/bin/env bash
set -euo pipefail
BACKUP_DIR=/mnt/backup
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=14

# Dump all databases
pg_dumpall -U postgres --clean --if-exists | gzip > "$BACKUP_DIR/pg_dumpall_${TIMESTAMP}.sql.gz"

# Rotate old backups
find "$BACKUP_DIR" -name 'pg_dumpall_*.sql.gz' -mtime +${RETENTION_DAYS} -delete

echo "Backup complete: pg_dumpall_${TIMESTAMP}.sql.gz"
```

#### Cron Schedule

```
# /etc/cron.d/pg-backup
0 2 * * * postgres /opt/homelab/pg-backup.sh >> /var/log/pg-backup.log 2>&1
```

#### Restore Verification

The restore procedure creates a scratch database on the same instance:

```bash
#!/usr/bin/env bash
set -euo pipefail
LATEST=$(ls -t /mnt/backup/pg_dumpall_*.sql.gz | head -1)
SCRATCH_DB="restore_verify_$(date +%s)"

# Create scratch database
psql -U postgres -c "CREATE DATABASE ${SCRATCH_DB};"

# Restore into scratch (targeting just the scratch db)
gunzip -c "$LATEST" | psql -U postgres -d "$SCRATCH_DB" 2>/dev/null

# Run basic integrity checks
psql -U postgres -d "$SCRATCH_DB" -c "SELECT count(*) FROM pg_tables WHERE schemaname = 'public';"

# Clean up
psql -U postgres -c "DROP DATABASE ${SCRATCH_DB};"

echo "Restore verification passed"
```

**Alternative**: For per-database backups, `pg_dump -Fc` (custom format) + `pg_restore` provides parallel restore and selective table recovery. `pg_dumpall` is simpler for full-instance logical backup and captures roles/tablespaces.

### 9. SOPS Secret Management

#### Established Pattern

From the gitops-smoke app, the pattern is:
1. Generate credentials outside git (e.g., `openssl rand -base64 32`)
2. Create a Kubernetes Secret YAML with plaintext values
3. Encrypt with `sops --encrypt --in-place secret.enc.yaml`
4. The `.sops.yaml` at `gitops/.sops.yaml` auto-selects the age key
5. Argo CD's SOPS CMP plugin decrypts during reconciliation

#### Secrets Needed for Phase 5

| Secret | Namespace | Contains |
|--------|-----------|----------|
| postgres-credentials | shared-services | PostgreSQL connection strings for apps |
| valkey-credentials | shared-services | Valkey connection URL |
| nats-credentials | shared-services | NATS connection URL |
| debezium-db-password | (on services-01, not k8s) | Debezium's PostgreSQL password |

For secrets that are consumed by the Compose VM (not k8s), they should be stored in a `.env` file on services-01, generated during provisioning and never committed to git.

### 10. OpenTofu for LXC and VM Provisioning

#### LXC Provisioning (postgres-01)

New OpenTofu root at `infrastructure/opentofu/postgres/`:
- `main.tf`: `proxmox_virtual_environment_container` + `proxmox_virtual_environment_download_file` (vztmpl)
- `variables.tf`: Same pattern as k3s (state_passphrase, ssh_public_key, proxmox_ssh_private_key)
- `outputs.tf`: Container IP and ID

LXC-specific differences from VM:
- Uses `proxmox_virtual_environment_container` (not `_vm`)
- Template is `vztmpl` content type (not `import`)
- `unprivileged = true` for security
- No cloud-init user-data file; uses `initialization` block directly
- `network_interface` instead of `network_device`
- `operating_system.type = "ubuntu"` instead of `operating_system.type = "l26"`

#### VM Provisioning (services-01)

New OpenTofu root at `infrastructure/opentofu/services/`:
- Follows the exact same pattern as `infrastructure/opentofu/k3s/`
- VMID 121, different allocations (4 vCPU, 8192 MiB, 64 GiB)
- Cloud-init template installs Docker + Docker Compose instead of k3s
- Startup order 20 (before k3s at 40, after postgres at 10)

#### Cloud-init for services-01

```yaml
#cloud-config
hostname: services-01
packages:
  - ca-certificates
  - curl
  - qemu-guest-agent
  - nfs-common
runcmd:
  - [systemctl, start, qemu-guest-agent]
  # Install Docker
  - [bash, -c, "curl -fsSL https://get.docker.com | sh"]
  - [usermod, -aG, docker, ubuntu]
  - [systemctl, enable, docker]
```

Docker Compose files would then be deployed to the VM via SCP/SSH from the provisioning script.

### 11. Docker Compose Organization for services-01

#### Recommended File Structure

```
infrastructure/services/
├── docker-compose.yaml         # Main compose file
├── nats.conf                   # NATS server configuration
├── debezium/
│   └── application.properties  # Debezium Server configuration (template)
└── .env.example                # Template for runtime secrets
```

The compose file lives in the homelab repo for version control. The deployment script copies it to services-01 and deploys.

#### Compose File Structure

```yaml
services:
  valkey:
    image: valkey/valkey:8-alpine
    # ... (see SERV-02 section above)
    restart: unless-stopped

  nats:
    image: nats:2-alpine
    # ... (see SERV-03 section above)
    restart: unless-stopped

  debezium:
    image: quay.io/debezium/server:3.0
    depends_on:
      nats:
        condition: service_healthy
    # ... (see SERV-04 section above)
    restart: unless-stopped

volumes:
  valkey-data:
  nats-data:
  debezium-data:
```

**Key principle**: Compose controls internal startup order via `depends_on` with health checks. Proxmox startup ordering only ensures services-01 VM starts after postgres-01 LXC.

### 12. Lifecycle Script Structure

Following the established `k3s-platform.sh` and `gitops-platform.sh` patterns:

#### scripts/postgres-platform.sh

Subcommands: `preflight | apply | configure | validate | backup | restore-test | destroy`

- `preflight`: Check tools, credentials, VMID 120 safety
- `apply`: `tofu apply` to create LXC 120
- `configure`: SSH to install PostgreSQL, deploy configs, create roles
- `validate`: Check PostgreSQL is accepting connections from k3s subnet
- `backup`: Trigger a backup and verify file exists on NFS
- `restore-test`: Restore latest backup to scratch DB and verify
- `destroy`: `tofu destroy`

#### scripts/services-platform.sh

Subcommands: `preflight | apply | deploy | validate | destroy`

- `preflight`: Check tools, credentials, VMID 121 safety
- `apply`: `tofu apply` to create VM 121
- `deploy`: SCP compose files, SSH to `docker compose up -d`
- `validate`: Check all three services are healthy
- `destroy`: `tofu destroy`

## Validation Architecture

### Static Tests (tests/test-shared-services.sh static)

1. **Inventory alignment**: Validate that OpenTofu locals match inventory.json for both guests
2. **Compose file validation**: `docker compose config` on the compose file
3. **GitOps manifest validation**: All selectorless Services have matching EndpointSlices with correct labels
4. **SOPS encryption check**: Encrypted files exist and contain no plaintext credentials
5. **No hardcoded IPs in k8s manifests**: Apps reference `*.shared-services.svc.cluster.local` names
6. **Credential leak scan**: No tokens/passwords in committed files

### Live Tests (tests/test-shared-services.sh live)

1. **PostgreSQL**: `pg_isready -h 10.10.30.100 -p 5432` from operator, and via k8s Job from cluster
2. **Valkey**: `valkey-cli -h 10.10.30.101 ping` returns PONG
3. **NATS**: HTTP health at `http://10.10.30.101:8222/healthz`, JetStream info at `/jsz`
4. **Debezium**: Health endpoint at `http://10.10.30.101:8080/q/health`
5. **k8s discovery**: Deploy a test Job in shared-services namespace that reaches all services via cluster DNS
6. **Zitadel**: `curl -fsS https://zitadel.kayage.co/.well-known/openid-configuration` returns valid OIDC metadata
7. **WAL bounds**: Query `pg_replication_slots` to verify Debezium slot exists and `max_slot_wal_keep_size` is set
8. **NATS limits**: Query `/jsz` to verify `max_file_store` is bounded
9. **Backup/restore**: Run backup, verify file on NFS, restore to scratch, verify data

### Proof Artifacts

- `.local/phase-05-services-proof`: Timestamp of successful connectivity test
- `.local/phase-05-backup-proof`: Timestamp of successful backup + restore verification

## Risks and Unknowns

### Risk 1: LXC NFS Mount Permissions (Medium)

Unprivileged LXC containers have UID mapping that can cause NFS permission issues. **Mitigation**: Mount NFS on the Proxmox host and use a bind mount point in the LXC container configuration. This is the standard Proxmox pattern and avoids the unprivileged container NFS mount problem entirely.

### Risk 2: Debezium Server NATS JetStream Maturity (Medium)

The NATS JetStream sink for Debezium Server is less commonly used than the Kafka sink. Subject pattern matching and stream auto-creation behavior may have edge cases. **Mitigation**: Test with a minimal table and verify end-to-end message delivery. Pin Debezium version and document exact working configuration.

### Risk 3: Debezium Slot Invalidation Recovery (Low)

If `max_slot_wal_keep_size` invalidates the slot, Debezium must re-snapshot. This is a designed safety mechanism but requires understanding the recovery path. **Mitigation**: Document the re-snapshot procedure. The heartbeat interval (30s) makes idle-period invalidation unlikely under normal operations.

### Risk 4: Compose VM Single Point of Failure (Accepted)

All three services (Valkey, NATS, Debezium) share VM 121. A VM failure affects all. **Mitigation**: This is an accepted design decision (Phase 1) — single MS-01 host provides no real hardware redundancy anyway. Valkey and NATS have durable persistence. Debezium is ephemeral and recoverable.

### Risk 5: Zitadel OIDC Issuer URL vs Cluster-Internal Name (Low)

OIDC flows require the issuer URL to be resolvable by both the browser and the backend. Using the cluster-internal name (`zitadel.shared-services.svc.cluster.local`) as the issuer would break browser redirects. **Mitigation**: Always use `https://zitadel.kayage.co` as the OIDC issuer. The selectorless Service is for health-check and non-browser backend calls only.

### Risk 6: PostgreSQL LXC Template Availability (Low)

The Ubuntu LXC container template URL format differs from the cloud-image format used for VMs. **Mitigation**: Use the standard Proxmox-hosted container templates or canonical container images from `images.linuxcontainers.org`. Verify the download URL and checksum before provisioning.

### Unknown 1: Debezium Server Password Injection

Debezium Server reads `application.properties` — it's unclear whether environment variable substitution (like `${DEBEZIUM_DB_PASSWORD}`) works natively or requires Quarkus-specific syntax (`${ENV_VAR}`). Quarkus does support `${ENV_VAR}` syntax. This should be verified with the actual image.

### Unknown 2: NFS Export Path on NAS

The exact NFS export path on the NAS at 10.10.40.2 must be confirmed with the operator. The research assumes a path like `/backup/postgres` exists or will be created.

### Unknown 3: PostgreSQL Version on Existing Zitadel

Zitadel's internal PostgreSQL (if any) is separate. This phase does not touch Zitadel's database. However, if Zitadel uses the new postgres-01 in the future, schema isolation will be important.

## RESEARCH COMPLETE
