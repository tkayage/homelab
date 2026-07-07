# Local wildcard edge

The local application rail is `*.app.kayage.co → 10.10.30.237 (NPM) → 10.10.30.102:80 (Traefik)`. NPM terminates a dedicated Let's Encrypt wildcard certificate issued through Cloudflare DNS-01. RouterOS and NPM are one-time external resources; each application owns only its Kubernetes Ingress in GitOps.

## Apply and verify

Credentials remain in `/home/tonny/.config/homelab/{mikrotik,npm,cloudflare}.env` and are never committed. Apply is idempotent and refuses an unowned wildcard conflict:

```bash
bash scripts/local-edge.sh apply
bash scripts/local-edge.sh status
bash scripts/local-edge.sh prove-zero-touch
bash tests/test-local-edge.sh live
```

The live suite queries RouterOS DNS directly, validates the trusted certificate and expiry, and tests Host routing, forwarded headers, websocket upgrade, and a 4 MiB request through NPM and Traefik. The zero-touch exercise adds and removes a second Ingress through Git while asserting that DNS, proxy, and certificate IDs remain unchanged.

## Add or remove an application

Add an Ingress with `ingressClassName: traefik` and a unique hostname below `app.kayage.co`. No router, NPM, Cloudflare, or certificate change is needed. Removing the application directory lets Argo CD prune the Ingress while the wildcard rail remains.

## Diagnose and recover

```bash
dig +short @10.10.30.1 edge-smoke.app.kayage.co A
curl --resolve edge-smoke.app.kayage.co:443:10.10.30.237 https://edge-smoke.app.kayage.co/headers
kubectl --kubeconfig .local/kubeconfig-k3s-01 -n argocd get application edge-smoke
kubectl --kubeconfig .local/kubeconfig-k3s-01 -n edge-smoke describe ingress edge-smoke
```

After rebuilding NPM or the router, rerun `apply`; ownership markers let it recreate or update only platform resources. Certificate renewal remains NPM's responsibility. The preflight confirms the Cloudflare token is active and apply refuses a public `*.app.kayage.co` record, preserving local-only exposure. If wildcard routing is ever unsupported after an upgrade, stop and implement the documented per-app API fallback rather than weakening conflict or public-exposure guards.
