# Phase 5: Shared Stateful Services - Pattern Mapping

This document maps the architectural requirements for Phase 5 to specific files and established patterns in the repository based on `05-CONTEXT.md` and `05-RESEARCH.md`.

## Files to be Created or Modified

### 1. PostgreSQL LXC Provisioning

#### `infrastructure/opentofu/postgres/main.tf` (and `variables.tf`, `outputs.tf`, `providers.tf`)
- **Role:** Provision a dedicated unprivileged LXC container (postgres-01, VMID 120) for PostgreSQL.
- **Data Flow:** OpenTofu -> Proxmox API -> LXC Container instance.
- **Closest Analog:** `infrastructure/opentofu/k3s/main.tf` (Established provider and state encryption pattern).
- **Concrete Code Excerpt:**
  ```hcl
  resource "proxmox_virtual_environment_container" "postgres" {
    node_name    = "proxmox"
    vm_id        = 120
    description  = "Dedicated PostgreSQL server managed by OpenTofu"
    tags         = ["opentofu", "postgres", "durable"]
    unprivileged = true
    
    startup {
      order      = "10"
      up_delay   = "30"
    }
    
    operating_system {
      template_file_id = proxmox_virtual_environment_download_file.ubuntu_lxc.id
      type             = "ubuntu"
    }
  }
  ```

#### `scripts/postgres-platform.sh`
- **Role:** Orchestrate the lifecycle, configuration, and backup/restore verification of the PostgreSQL LXC.
- **Data Flow:** Operator -> Bash -> OpenTofu CLI / SSH -> LXC 120 / NFS Backup Share.
- **Closest Analog:** `scripts/k3s-platform.sh` (Lifecycle subcommand pattern).
- **Concrete Code Excerpt:**
  ```bash
  case ${1:-} in
    preflight) preflight ;;
    apply) apply_lxc ;;
    configure) configure_postgres ;;
    validate) validate_postgres ;;
    backup) backup_postgres ;;
    restore-test) restore_test_postgres ;;
    destroy) destroy_lxc ;;
    *) fail "usage: $0 {preflight|apply|configure|validate|backup|restore-test|destroy}" ;;
  esac
  ```

### 2. Shared Services VM Provisioning

#### `infrastructure/opentofu/services/main.tf` (and related tofu files)
- **Role:** Provision VM 121 (services-01) for Valkey, NATS, and Debezium.
- **Data Flow:** OpenTofu -> Proxmox API -> VM 121.
- **Closest Analog:** `infrastructure/opentofu/k3s/main.tf`.
- **Concrete Code Excerpt:**
  ```hcl
  resource "proxmox_virtual_environment_vm" "services" {
    name            = "services-01"
    vm_id           = 121
    tags            = ["opentofu", "services", "durable"]
    
    cpu { cores = 4 }
    memory { dedicated = 8192 }
    
    initialization {
      user_data_file_id = proxmox_virtual_environment_file.cloud_init.id
    }
  }
  ```

#### `infrastructure/opentofu/services/cloud-init.yaml.tftpl`
- **Role:** Configure the underlying OS for services-01 and install Docker engine.
- **Data Flow:** Proxmox Snippet -> cloud-init -> VM 121 OS.
- **Closest Analog:** `infrastructure/opentofu/k3s/cloud-init.yaml.tftpl`.
- **Concrete Code Excerpt:**
  ```yaml
  #cloud-config
  hostname: services-01
  runcmd:
    - [bash, -c, "curl -fsSL https://get.docker.com | sh"]
    - [usermod, -aG, docker, ubuntu]
    - [systemctl, enable, docker]
  ```

#### `scripts/services-platform.sh`
- **Role:** Orchestrate the services VM lifecycle and the deployment of the Compose stack.
- **Data Flow:** Operator -> Bash -> OpenTofu CLI / SSH -> VM 121 / Docker.
- **Closest Analog:** `scripts/k3s-platform.sh`.
- **Concrete Code Excerpt:**
  ```bash
  case ${1:-} in
    preflight) preflight ;;
    apply) apply_vm ;;
    deploy) deploy_compose ;;
    validate) validate_services ;;
    destroy) destroy_vm ;;
    *) fail "usage: $0 {preflight|apply|deploy|validate|destroy}" ;;
  esac
  ```

### 3. Docker Compose Application Layer

#### `infrastructure/services/docker-compose.yaml` (plus configs: `nats.conf`, `application.properties`)
- **Role:** Define the interconnected multi-container deployment for Valkey, NATS, and Debezium.
- **Data Flow:** Docker Compose -> Docker Engine -> Container runtime.
- **Closest Analog:** Standard Compose file (First of its kind in this repository).
- **Concrete Code Excerpt:**
  ```yaml
  services:
    debezium:
      image: quay.io/debezium/server:3.0
      depends_on:
        nats:
          condition: service_healthy
      volumes:
        - ./debezium/application.properties:/debezium/conf/application.properties:ro
  ```

### 4. Kubernetes Discovery (GitOps)

#### `gitops/apps/shared-services/kustomization.yaml` (with `service-*.yaml` & `endpointslice-*.yaml`)
- **Role:** Expose off-cluster stateful services securely to k3s apps using stable DNS names.
- **Data Flow:** Git -> Argo CD -> Kubernetes API -> CoreDNS/Kube-proxy.
- **Closest Analog:** `gitops/apps/gitops-smoke/kustomization.yaml`.
- **Concrete Code Excerpt:**
  ```yaml
  # endpointslice-postgres.yaml
  apiVersion: discovery.k8s.io/v1
  kind: EndpointSlice
  metadata:
    name: postgres-1
    namespace: shared-services
    labels:
      kubernetes.io/service-name: postgres
      endpointslice.kubernetes.io/managed-by: homelab-gitops
  endpoints:
    - addresses:
        - "10.10.30.100"
      conditions:
        ready: true
  ```

### 5. Validation and Testing

#### `tests/test-shared-services.sh`
- **Role:** Validate static configurations and perform live cluster connectivity testing against all provisioned stateful services.
- **Data Flow:** Operator / CI -> Bash -> Local Filesystem / Cluster API / SSH.
- **Closest Analog:** `tests/test-k3s-foundation.sh`.
- **Concrete Code Excerpt:**
  ```bash
  static_checks() {
    tofu -chdir="$root/infrastructure/opentofu/postgres" fmt -check
    # Validates configurations and OpenTofu variables
  }
  
  case ${1:-static} in
    static) static_checks ;;
    live) static_checks; "$root/scripts/services-platform.sh" validate ;;
    *) printf 'usage: %s {static|live}\n' "$0" >&2; exit 2 ;;
  esac
  ```

## PATTERN MAPPING COMPLETE
