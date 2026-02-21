## What This Repo Contains

### Application

- FastAPI application implementing document validation and metrics instrumentation

  - Location: `app/`

    - `app/main.py` — validation logic + metrics instrumentation
    - `app/ui.html` — validation and traffic simulation interface
    - `app/static/` — UI assets (CSS/JS/logo)
    - `app/requirements.txt` — Python dependencies
    - `app/__init__.py` — application module initialization

  - Tests:

    - `test_validation.py` — unit tests (pytest)

  - Exposed endpoints:

    - `POST /validate` — validates payload and returns `ACCEPTED` or `REJECTED`
    - `GET /metrics` — Prometheus metrics endpoint
    - `GET /health/live` — liveness probe
    - `GET /health/ready` — readiness probe
    - `GET /ui` — validation UI

### Helm Chart

- Kubernetes packaging for the document-service application

  - Location: `helm/document-service/`

    - `templates/deployment.yaml` — Deployment with probes + resource limits
    - `templates/service.yaml` — ClusterIP service definition
    - `templates/servicemonitor.yaml` — Prometheus Operator scraping configuration (ServiceMonitor)
    - `values.yaml` — image reference, replica count, resource configuration

### GitOps

- Argo CD Application manifest (example):
  - `argocd/document-service-app.yaml`

### CI

- GitHub Actions workflow:
  - `.github/workflows/ci.yml`