# Internal Document Platform (Document Validation Service)
![CI](https://github.com/moel1001/internal-document-platform-/actions/workflows/ci.yml/badge.svg?branch=main)

A cloud-native backend service deployed via **GitOps** (Argo CD) with **CI/CD** (GitHub Actions → GHCR) and full **observability** (Prometheus + Grafana).

---

## What this project demonstrates
- Building a small, real backend service (FastAPI) with production-style endpoints
- Containerization with Docker
- Kubernetes deployment on a local cluster (**kind**)
- Packaging and configuration with **Helm**
- Image build/push automation with **GitHub Actions**
- GitOps-based deployments with **Argo CD**
- Metrics scraping with **Prometheus Operator** via **ServiceMonitor**
- Dashboarding with **Grafana** (traffic + latency panels)

---
## Project scope

This project is intentionally designed as a **local, reproducible platform setup**
to demonstrate modern cloud-native practices (CI/CD, GitOps, observability)
without relying on managed cloud services.

It focuses on correctness, visibility, and automation rather than feature completeness.

## Architecture

![Architecture diagram](docs/diagrams/architecture.svg)

---
## What This Repo Contains

### Application
- **FastAPI service** (document validation)
- Endpoints:
  - `POST /validate` — validates payload and returns `ACCEPTED` or `REJECTED`
  - `GET /metrics` — Prometheus metrics
  - `GET /health/live` — liveness probe
  - `GET /health/ready` — readiness probe

### Helm Chart
Location: `helm/document-service/`

- `templates/deployment.yaml` — Deployment with probes + resources
- `templates/service.yaml` — ClusterIP service
- `templates/servicemonitor.yaml` — Prometheus Operator scraping config (ServiceMonitor)
- `values.yaml` — image + replicaCount + resources

### GitOps
- Argo CD Application manifest (example):
  - `argocd/document-service-app.yaml`

### CI
- GitHub Actions workflow:
  - `.github/workflows/ci.yml`
- Builds + pushes image to GHCR (tags typically include `latest` and a commit SHA)

## CI verification

- GitHub → Actions: latest workflow run should be green
- GitHub → Packages: container image published to GHCR

Image tags typically include:
- `latest`
- commit SHA
---

## Service Behavior

### Validation Rules
A request is **ACCEPTED** only if:
- `document_id` is not empty
- `document_type` is one of: `invoice`, `delivery_note`, `certificate`
- `created_at` matches `YYYY-MM-DD`
- `source_system` is not empty

Otherwise it is **REJECTED** with a `reason`.

### Metrics (Prometheus)
Exposed on `/metrics` using `prometheus_client`:

- `document_validation_requests_total` (Counter)  
- `document_validation_failures_total` (Counter)  
- `document_validation_request_latency_seconds` (Histogram)

---

## Quickstart (5 minutes)

### Prerequisites
- Docker Desktop
- kubectl, kind, helm
- (Optional) argocd CLI

### Run locally (Docker)
```bash
docker build -t document-service:0.1.0 .
docker run --rm -p 8000:8000 document-service:0.1.0
```
### Test endpoints

#### Health:

```bash
curl -s http://localhost:8000/health/live && echo
curl -s http://localhost:8000/health/ready && echo
```

#### Validate (Accepted)
```bash
curl -s -X POST http://localhost:8000/validate \
  -H 'Content-Type: application/json' \
  -d '{"document_id":"INV-001","document_type":"invoice","created_at":"2025-01-10","source_system":"erp"}' && echo
```

#### Validate (Rejected)
```bash
curl -s -X POST http://localhost:8000/validate \
  -H 'Content-Type: application/json' \
  -d '{"document_id":"","document_type":"invoice","created_at":"2025-01-10","source_system":"erp"}' && echo
```
#### Metrics
```bash
curl -s http://localhost:8000/metrics | head -n 25
curl -s http://localhost:8000/metrics | grep document_validation_requests_total
```

### Deploy to Kubernetes (kind + Helm)

```bash
kind create cluster --name dev-platform
kubectl get nodes
kubectl create namespace platform
```

### Install via Helm

```bash
helm upgrade --install document-service helm/document-service -n platform
```
### In-cluster verification

Verify Deployment and Service:
```bash
kubectl get deploy,svc -n platform
```

Verify Pods selected by Service:
```bash
kubectl get pods -n platform -l app=document-service
```
> If label selectors return nothing, run: `kubectl get pods -n platform --show-labels` and adjust the selector.

Verify Service endpoints:
```bash
kubectl get endpoints -n platform document-service
```

### Watch pods and check readiness

```bash
kubectl get pods -n platform -w
```

### Check logs (all pods)

```bash
kubectl logs -n platform -l app=document-service
```

### Port-forward service
```bash
kubectl port-forward -n platform svc/document-service 8000:8000
```
---

## GitOps demo (Argo CD): Git changes → cluster updates

### Apply Argo CD Application

```bash
kubectl apply -f argocd/document-service-app.yaml
```

### Watch Argo status

```bash
kubectl port-forward -n argocd svc/argocd-server 8080:443
```
### get Argo CD admin password (first login)

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 --decode && echo
```
Login (user: admin, password: output above):

```bash
argocd login localhost:8080 --username admin --password <PASTE_PASSWORD> --insecure
```

```bash
argocd app get document-service
```
### Sync application (if not auto-sync)

```bash
argocd app sync document-service
argocd app wait document-service
```

### Change replicas in Git and push

Edit : helm/document-service/values.yaml

Example:

```yaml
replicaCount: 4
```

Commit + push:

```bash
git add helm/document-service/values.yaml
git commit -m "gitops: change replicaCount to 4"
git push
```

### Observe Kubernetes reconcile automatically

```bash
kubectl get pods -n platform -w
```

Expected:
**pods get created/terminated until the replica count matches Git.**

## Observability: Prometheus + Grafana verification

### Install Monitoring stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
kubectl create ns monitoring
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack -n monitoring
```

### Confirm ServiceMonitor exists

```bash
kubectl get servicemonitor -n platform
kubectl describe servicemonitor -n platform document-service
```

### Port-forward Prometheus UI (service name may differ)

```bash
kubectl get svc -n monitoring
```

```bash
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090
# or (depending on chart/service)
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-stack-prometheus 9090:9090
```

Open Prometheus at: http://localhost:9090

Check:

Status → Targets
confirm document-service target is UP

### Generate traffic for graphs
```bash
for i in {1..30}; do
  curl -s -X POST http://localhost:8000/validate \
    -H 'Content-Type: application/json' \
    -d "{\"document_id\":\"INV-$i\",\"document_type\":\"invoice\",\"created_at\":\"2025-01-10\",\"source_system\":\"erp\"}" \
    >/dev/null
done
```

### PromQL queries

**Total Requests :**

```promql
document_validation_requests_total
```

**Requests per second:**

```promql
rate(document_validation_requests_total[1m])
```
**P95 latency (5m window for more stable results):**

```promql
histogram_quantile(0.95, rate(document_validation_request_latency_seconds_bucket[5m]))
```
If p95 shows NaN, there may be too few samples in the time window. Generate more traffic and widen the window.

### Port-forward Grafana and login

List services: 

```bash
kubectl get svc -n monitoring
```

Common Grafana service name:

```bash
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
```
Fetch admin password:

```bash
kubectl get secret -n monitoring monitoring-grafana \
  -o jsonpath='{.data.admin-password}' | base64 --decode && echo

```

Open Grafana at : http://localhost:3000

Login:

user: admin
password: (from command above)

## Key outcomes

- CI builds and publishes container images automatically
- Git is the single source of truth for runtime configuration
- Kubernetes state converges automatically via Argo CD
- Application behavior is observable via metrics and dashboards

## Non-goals
- No ingress or authentication
- No persistent storage
- No managed cloud services
