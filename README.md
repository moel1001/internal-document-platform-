# Internal Document Platform (Document Validation Service)
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

