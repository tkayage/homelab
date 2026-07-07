---
phase: 02-reproducible-k3s-foundation
date: 2026-07-07
status: complete
---

# Phase 2 Research

Use OpenTofu 1.12.x with `bpg/proxmox` 0.111.x. The provider supports direct cloud-image import, custom cloud-init user data, fixed VM identity, startup ordering, and QEMU guest-agent integration. Use Ubuntu 24.04 LTS released cloud image with a pinned SHA-256 checksum. Pin k3s `v1.34.9+k3s1`; configure it through `/etc/rancher/k3s/config.yaml`, retain bundled Traefik, and keep kubeconfig mode 0600. Local OpenTofu state and plans require at-rest encryption and git exclusion because state can contain sensitive attributes.

Validation must cover OpenTofu formatting/validation, exact Phase 1 inventory alignment, cloud-init syntax, API VM state, SSH readiness, Kubernetes node/system-pod health, Traefik service availability, absence of application local-path persistence, and actual destroy/recreate using identical inputs.

Primary references: OpenTofu state/encryption and provider-requirement documentation; bpg/proxmox provider 0.111 VM/cloud-init documentation; K3s configuration and v1.34 release notes; Ubuntu 24.04 released cloud-image checksums.
