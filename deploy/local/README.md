# Local access (no port-forwarding)

This folder provides a lightweight way to access the platform UIs on a local kind cluster without running `kubectl port-forward`.

It works by:
1. Creating Kubernetes Ingress objects for friendly hostnames (`grafana.local`, `prometheus.local`, `argocd.local`, `document-service.local`)
2. Running a small nginx proxy container on the Docker `kind` network to forward traffic from your machine (ports 80/443) to the ingress-nginx NodePorts inside kind
3. Generating a local self-signed TLS cert for `https://argocd.local`

## Prerequisites

- A kind cluster is running
- `ingress-nginx` is installed in the cluster (namespace `ingress-nginx`)
- Docker network `kind` exists (created by kind)
- Your machine resolves the hostnames to `127.0.0.1`

Quick checks:

```bash
kubectl -n ingress-nginx get svc ingress-nginx-controller
docker network ls | grep kind
```

## Hostname setup

You must map these names to localhost on your machine:

```bash
127.0.0.1 grafana.local
127.0.0.1 prometheus.local
127.0.0.1 argocd.local
127.0.0.1 document-service.local
```

How to do that depends on your OS:

* macOS / Linux: add the lines to `/etc/hosts`
* Windows: add the lines to `C:\Windows\System32\drivers\etc\hosts` (run editor as Administrator)

Verification:

* macOS:

  ```bash
  dscacheutil -q host -a name grafana.local
  ```
* Linux:

  ```bash
  getent hosts grafana.local
  ```
* Windows (PowerShell):

  ```powershell
  Resolve-DnsName grafana.local
  ```

## Start

From the repository root:

```bash
./deploy/local/bootstrap.sh
```

It will:

* verify hostname resolution
* verify ingress-nginx + Docker network
* generate a local TLS cert for `argocd.local` (stored in `deploy/local/certs/`)
* apply local ingresses (`deploy/local/ingress-local.yaml`)
* start the local proxy container (`idp-local-proxy`)
* run basic smoke tests

Open:

* [http://grafana.local](http://grafana.local)
* [http://prometheus.local](http://prometheus.local)
* [https://argocd.local](https://argocd.local)
* [http://document-service.local](http://document-service.local)

Note: `argocd.local` uses a self-signed certificate, so your browser may show a warning. Proceed to the site.

## Stop / cleanup

```bash
./deploy/local/teardown.sh
```

This will:

* stop the proxy container
* delete the local ingress objects
* remove generated local files (`deploy/local/certs`, `deploy/local/.runtime`)

## Troubleshooting

Check proxy container:

```bash
docker ps --filter name=idp-local-proxy
docker logs --tail=100 idp-local-proxy
```

Check ingresses exist:

```bash
kubectl get ingress -A | egrep 'grafana|prometheus|argocd|document-service'
```

Check ports 80/443 are free on your machine (macOS / Linux):

```bash
sudo lsof -nP -iTCP:80 -sTCP:LISTEN
sudo lsof -nP -iTCP:443 -sTCP:LISTEN
```

## Files overview

* `bootstrap.sh` / `teardown.sh` – main entrypoints for local UI access
* `ingress-local.yaml` – Ingress objects for local hostnames
* `nginx-proxy.conf.tpl` – nginx template used by the proxy container
* `scripts/proxy-up.sh` – starts proxy container + generates runtime config
* `scripts/proxy-down.sh` – stops proxy container
* `scripts/cert-gen.sh` – generates self-signed cert for `argocd.local`

Generated (not committed):

* `deploy/local/certs/` – local TLS cert + key
* `deploy/local/.runtime/` – generated nginx.conf used by the proxy

