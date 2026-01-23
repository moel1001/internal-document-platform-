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
