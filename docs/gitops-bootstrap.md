# GitOps bootstrap and recovery

Argo CD v3.4.2 reconciles the private `tkayage/gitops-homelab` repository. The `platform-root` Application owns the ApplicationSet, and its Git directory generator discovers every `apps/*` directory. Platform-root pruning is disabled. Generated applications use prune/self-heal, but `preserveResourcesOnDeletion: true` and the absence of deletion finalizers prevent cascading deletion when an Application or ApplicationSet is removed.

## Bootstrap or recover

The only off-cluster recovery inputs are the kubeconfig, `/home/tonny/.config/homelab/github.env`, and `/home/tonny/.config/homelab/age/keys.txt`. The age key must remain mode 0600 and backed up outside the k3s VM. After cluster replacement, retrieve the fresh kubeconfig first, then run:

```bash
bash scripts/gitops-platform.sh bootstrap
bash tests/test-gitops-bootstrap.sh live
```

Bootstrap applies the age key and private GitHub repository credential before creating the root Application. Neither credential is committed. SOPS decrypts `*.enc.yaml` inside an ephemeral Config Management Plugin work directory and feeds the result to Kustomize.

## Observe and diagnose

```bash
bash scripts/gitops-platform.sh status
kubectl --kubeconfig .local/kubeconfig-k3s-01 -n argocd logs deployment/argocd-repo-server -c sops-kustomize
bash scripts/gitops-platform.sh ui
```

The UI helper forwards the Argo CD service to `https://127.0.0.1:8443`; it does not expose the management service on the LAN. CLI status is the primary health path.

## Roll back

Normal rollback is a Git revert in the GitOps repository. The acceptance exercise safely automates a bad-image commit, observes reconciliation, reverts that exact commit, and waits for recovery:

```bash
bash scripts/gitops-platform.sh prove-rollback
```

Do not delete the root or ApplicationSet as an operational rollback mechanism. Explicitly add an Argo deletion finalizer only for a reviewed resource whose cascade behavior is intended.
