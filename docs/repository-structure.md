# Repository Structure

This repository contains a production-style, demo-grade internal document
validation platform. The project started with a local KinD validation
environment and was later extended to AWS EKS using the same Helm, Argo CD, and
CI/CD delivery model.

## Application

Location: `app/`

FastAPI service implementing document validation, Prometheus metrics,
Kubernetes health checks, and a lightweight validation and traffic simulation
UI.

Key files:

- `app/main.py` - validation API, health checks, metrics, and UI routes
- `app/ui.html` - browser-based validation and traffic simulation interface
- `app/static/` - UI assets such as CSS, JavaScript, and logo files
- `app/requirements.txt` - Python runtime dependencies
- `tests/test_validation.py` - pytest coverage for validation behavior

Exposed endpoints:

- `POST /validate` - validates payloads and returns `ACCEPTED` or `REJECTED`
- `GET /metrics` - Prometheus metrics endpoint
- `GET /health/live` - liveness probe
- `GET /health/ready` - readiness probe
- `GET /ui` - validation and traffic simulation UI

## Container Image

Location: `Dockerfile`

Defines the application container used by CI and Kubernetes. The main CI
workflow builds the image, tests the built container, scans it, publishes it to
GitHub Container Registry, and updates the Helm image tag for GitOps release.

## Application Helm Chart

Location: `helm/document-service/`

Kubernetes packaging for the validation service.

Key files:

- `Chart.yaml` - chart metadata
- `values.yaml` - default values used by the local/KinD path
- `values-eks.yaml` - EKS-specific overrides
- `templates/deployment.yaml` - application Deployment with probes and resource settings
- `templates/service.yaml` - Kubernetes Service
- `templates/ingress.yaml` - ingress resource for external access where enabled
- `templates/servicemonitor.yaml` - Prometheus Operator scraping configuration

## Platform Helm Values

Location: `helm/platform-values/`

Versioned values for third-party platform charts managed through Argo CD.

Includes values for:

- `kube-prometheus-stack` - Prometheus, Grafana, Alertmanager, and exporters
- `loki-stack` - Loki and Promtail logging stack
- `aws-load-balancer-controller` - AWS Application Load Balancer integration for EKS

Separate local and EKS values files are kept where the deployment environments
need different settings.

## GitOps

Location: `argocd/`

Argo CD `Application` manifests define the desired Kubernetes state.

The repository includes both local and EKS-oriented application manifests,
including:

- `document-service` - deploys the validation service from the internal Helm chart
- `monitoring` - deploys kube-prometheus-stack
- `loki` - deploys the logging stack
- `aws-load-balancer-controller` - deploys AWS ingress controller integration for EKS
- `observability-config` - provisions Grafana dashboards through GitOps-managed ConfigMaps
- EKS ingress helper manifests for Grafana, Argo CD, Prometheus, and the document service

## AWS Infrastructure

Location: `infra/terraform/`

Terraform configuration for the AWS foundation used by the EKS environment.

Key responsibilities:

- VPC and subnet layout
- EKS cluster
- Managed node group
- IAM resources
- AWS Load Balancer Controller integration
- Public-safe example variables in `terraform.tfvars.example`

Local state, plans, backend files, and private variable files are intentionally
ignored by Git.

## EKS Lifecycle Scripts

Location: `infra/apply/`, `infra/destroy/`, and `infra/script-common.sh`

Operational scripts coordinate the demo environment lifecycle.

Usage and behavior are documented in `infra/README.md`.

Apply path:

- `infra/apply/apply-full-stack.sh` - full EKS platform creation and bootstrap flow
- `infra/apply/apply.sh` - Terraform apply wrapper
- `infra/apply/bootstrap-argocd.sh` - Argo CD installation and application bootstrap
- `infra/apply/prepare-aws-load-balancer-controller.sh` - load balancer controller preparation

Destroy path:

- `infra/destroy/teardown-workloads.sh` - removes Kubernetes workloads before infrastructure teardown
- `infra/destroy/cleanup-orphaned-elbs.sh` - cleans up leftover AWS load balancers
- `infra/destroy/destroy.sh` - Terraform destroy wrapper

Shared behavior lives in `infra/script-common.sh`.

## Observability Configuration

Location: `observability/grafana/`

Grafana dashboard configuration for the application observability story.

Key files:

- `dashboards/document-validation-service-observability.json` - request, rejection, and document-type dashboard
- `dashboards/Latency.json` - latency and performance dashboard
- `Chart.yaml` and `templates/dashboard-configmaps.yaml` - Helm chart that packages dashboard JSON into labeled ConfigMaps for Grafana sidecar discovery

## Local Access

Location: `deploy/local/`

Optional local convenience layer used during the KinD-based project phase.

Includes:

- Local ingress manifest
- Nginx proxy configuration template
- Local certificate generation
- Proxy start and stop scripts
- Local access documentation

## CI/CD Workflows

Location: `.github/workflows/`

GitHub Actions workflows cover application, infrastructure, and documentation
validation.

Main workflow:

- Python formatting and linting
- Unit tests
- Python compile sanity check
- Dependency vulnerability scan
- Docker build
- Built-container smoke test
- Container vulnerability scan
- GHCR release image publishing
- Helm image tag update for GitOps release

Infrastructure validation:

- Terraform formatting, initialization, validation, linting, and security scanning
- Helm linting and rendering for local and EKS values
- Kubernetes manifest schema validation
- Argo CD manifest validation
- Bash syntax checks and ShellCheck
- Dockerfile linting
- Secret scanning

Documentation validation:

- Markdown and README link checking
- Documentation-only path triggers

## Documentation

Location: `docs/`

Project documentation, diagrams, screenshots, and design notes.

Important files:

- `docs/local-development.md` - local development workflow
- `docs/design-decisions.md` - design decision record
- `docs/diagrams/` - architecture and pipeline diagrams
- `docs/screenshots/` - UI, Grafana, and Argo CD screenshots

Local planning notes such as `docs/portfolio-readiness-roadmap.md` are useful
for project work but are not part of the public documentation set unless
intentionally staged and reviewed.
