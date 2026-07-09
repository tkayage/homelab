# Fintrack Deployment Runbook

Fintrack is deployed as an outbound-only daemon. It must not have a Kubernetes
Service, Ingress, public exposure annotation, or inbound health listener.

## Current Deployment

- Source project: `/home/tonny/fintrack`
- GitOps app: `.local/gitops-homelab/apps/fintrack`
- Argo CD Application: `fintrack`
- Namespace: `fintrack`
- Image: `ghcr.io/tkayage/fintrack:5461131698d6-20260709090701`
- Image digest: `sha256:77f436a929c9695156610fd1a116e067571ae2a537782d5fe61dbbd90473d6c5`
- GitOps commit: `473fb41 deploy(fintrack): register daemon app`
- Runtime secret commit: `3e74e46 deploy(fintrack): configure runtime secret`

The workload has:

- `Deployment/fintrack`
- `PersistentVolumeClaim/fintrack-data` mounted at `/data`
- `Secret/ghcr-pull` for private GHCR image pulls
- `Secret/fintrack-runtime` for daemon environment and `allowlist.json`

## Required Runtime Configuration

The daemon will not become healthy until `fintrack-runtime` contains real values:

- `CLOUDFLARE_ACCOUNT_ID`
- `CLOUDFLARE_API_TOKEN`
- `CF_QUEUE_ID`
- `SURE_URL`
- `SURE_API_KEY`
- `ALERT_FROM`
- `ALERT_TO`
- optional `ALERT_API_TOKEN`
- `allowlist.json`

Do not commit plaintext runtime values. Update `apps/fintrack/runtime-secret.enc.yaml`
by rendering a plaintext `runtime-secret.yaml` in a private temporary directory,
encrypting it with SOPS, then replacing only the encrypted file.

The private operator copy currently lives at:

- `/home/tonny/.config/homelab/fintrack.env` with mode `0600`

## Verify

```bash
KUBECONFIG=.local/kubeconfig-k3s-01 kubectl -n argocd get application fintrack
KUBECONFIG=.local/kubeconfig-k3s-01 kubectl -n fintrack get pods,pvc
KUBECONFIG=.local/kubeconfig-k3s-01 kubectl -n fintrack logs deployment/fintrack --tail=100
```

Expected healthy startup logs include:

- allowlist loaded
- startup OK
- dedupe store opened
- fintrack daemon started

## Diagnose

If Argo does not discover the app, inspect the ApplicationSet and repo credential:

```bash
KUBECONFIG=.local/kubeconfig-k3s-01 kubectl -n argocd get applicationset homelab-apps -o yaml
KUBECONFIG=.local/kubeconfig-k3s-01 kubectl -n argocd logs deployment/argocd-applicationset-controller --tail=100
```

If logs show `authentication required`, rotate the `gitops-homelab-repository`
Secret from `/home/tonny/.config/homelab/github.env`, using the same shape as
`scripts/gitops-platform.sh`.

## Roll Back

Normal rollback is a Git revert in `.local/gitops-homelab`:

```bash
git -C .local/gitops-homelab revert <bad-commit>
git -C .local/gitops-homelab push origin main
KUBECONFIG=.local/kubeconfig-k3s-01 kubectl -n argocd get application fintrack
```

Argo CD automated sync applies the reverted state. Because the ApplicationSet uses
`preserveResourcesOnDeletion`, deleting the app directory should not be used as a
data cleanup shortcut; decide separately whether to retain or remove the PVC.

## Recovery

After cluster replacement, bootstrap Argo CD, SOPS age key, and the GitOps
repository credential first. The ApplicationSet will rediscover `apps/fintrack`.
The daemon state is only as durable as the `fintrack-data` PVC backing store on
the k3s node; off-node backup of `/data/dedupe.db` is not yet automated.
