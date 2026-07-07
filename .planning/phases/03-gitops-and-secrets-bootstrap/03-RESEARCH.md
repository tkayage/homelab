---
phase: 03-gitops-and-secrets-bootstrap
date: 2026-07-07
status: complete
---

# Phase 3 Research

Use Argo CD v3.4.2 from its pinned upstream non-HA manifest. Bootstrap the private repository credential and root Application from external operator credentials, then let Argo CD own all subsequent cluster resources. An ApplicationSet Git directory generator over `apps/*` provides automatic discovery. The platform root disables pruning, generated application children enable automated prune/self-heal, and `preserveResourcesOnDeletion` plus omission of deletion finalizers prevents an ApplicationSet or root deletion from cascading into workloads.

Use SOPS v3.13.2 with age. Keep the age private key in `/home/tonny/.config/homelab/age/keys.txt` (0600), create its cluster copy imperatively during bootstrap, and commit only its public recipient and SOPS ciphertext. Run decryption in a config-management-plugin sidecar. The plugin copies the application source to a temporary directory, decrypts `*.enc.yaml` files to their corresponding `*.yaml` paths, and runs Kustomize there, so plaintext never enters git or the Argo repository working tree.

Verification must prove root and generated Applications are Synced/Healthy, a discovered test workload consumes a decrypted Secret, plaintext is absent from both repositories, platform prune is disabled, generated app prune/self-heal is enabled, and a controlled bad Git commit followed by `git revert` restores health. Recovery verification re-applies the external age key and repository credential before the root Application.

Primary references: official Argo CD v3.4.2 release/install manifests, ApplicationSet Git directory generator and automated sync documentation, Config Management Plugin sidecar documentation, and official SOPS age documentation/releases.
