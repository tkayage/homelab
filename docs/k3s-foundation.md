# Reproducible k3s foundation

VM `k3s-01` is a disposable application cluster managed by OpenTofu. Its canonical identity is VMID 122 at `10.10.30.102` (`k3s.app.kayage.co`) with 4 vCPU, 8192 MiB RAM, and 64 GiB disk. Durable application data is prohibited inside this cluster.

## Commands

Run from the repository root:

- `bash scripts/k3s-platform.sh preflight` — validate tools, credentials, permissions, storage, and VMID safety.
- `bash scripts/k3s-platform.sh apply` — provision and bootstrap the VM.
- `bash scripts/k3s-platform.sh validate` — retrieve a fresh local kubeconfig and verify node, system pods, Traefik, agents, LAN identity, and persistence policy.
- `bash scripts/k3s-platform.sh replace` — destroy and recreate the disposable VM, then run live validation.
- `bash scripts/k3s-platform.sh destroy` — remove the managed VM and generated kubeconfig.

Credentials remain in `/home/tonny/.config/homelab/proxmox.env`; generated state encryption material and kubeconfig remain under `.local/`, mode 0600, and are excluded from git. OpenTofu state and saved plans are encrypted and excluded from git.

## Recovery

Run `replace` using the same committed inputs. A fresh kubeconfig is retrieved after the new SSH host becomes ready. Phase 3 restores Kubernetes desired state through GitOps; no application data recovery is expected from this disposable VM.

On failure, inspect the OpenTofu error category, Proxmox task status, cloud-init journal, `systemctl status k3s qemu-guest-agent`, and kube-system pod events. Do not paste tokens, authorization headers, kubeconfig client keys, state files, or raw authenticated API responses into logs or issues.
