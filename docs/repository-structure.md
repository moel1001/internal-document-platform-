# Repository Structure

This repository contains a production-style, demo-grade internal document
validation platform. The project started with a local KinD validation
environment and was later extended to AWS EKS using the same Helm, Argo CD, and
CI/CD delivery model.

## Application

Location: [`app/`](../app/)

FastAPI service implementing document validation, Prometheus metrics,
Kubernetes health checks, and a lightweight validation and traffic simulation
UI.

Key files:

- [`app/main.py`](../app/main.py) - validation API, health checks, metrics,
  and UI routes
- [`app/ui.html`](../app/ui.html) - browser-based validation and traffic
  simulation interface
- [`app/static/`](../app/static/) - UI assets such as CSS, JavaScript, and logo
  files
- [`app/requirements.txt`](../app/requirements.txt) - Python runtime
  dependencies
- [`tests/test_validation.py`](../tests/test_validation.py) - pytest coverage
  for validation behavior

Exposed endpoints:

- `POST /validate` - validates payloads and returns `ACCEPTED` or `REJECTED`
- `GET /metrics` - Prometheus metrics endpoint
- `GET /health/live` - liveness probe
- `GET /health/ready` - readiness probe
- `GET /ui` - validation and traffic simulation UI

## Container Image

Location: [`Dockerfile`](../Dockerfile)

Defines the application container used by CI and Kubernetes. The main CI
workflow builds the image, tests the built container, scans it, publishes it to
GitHub Container Registry, and updates the Helm image tag for GitOps release.

## Application Helm Chart

Location: [`helm/document-service/`](../helm/document-service/)

Kubernetes packaging for the validation service.

Key files:

- [`Chart.yaml`](../helm/document-service/Chart.yaml) - chart metadata
- [`values.yaml`](../helm/document-service/values.yaml) - default values used
  by the local/KinD path
- [`values-eks.yaml`](../helm/document-service/values-eks.yaml) - EKS-specific
  overrides
- [`templates/deployment.yaml`](../helm/document-service/templates/deployment.yaml)
  - application Deployment with probes and resource settings
- [`templates/service.yaml`](../helm/document-service/templates/service.yaml)
  - Kubernetes Service
- [`templates/ingress.yaml`](../helm/document-service/templates/ingress.yaml)
  - ingress resource for external access where enabled
- [`templates/servicemonitor.yaml`](../helm/document-service/templates/servicemonitor.yaml)
  - Prometheus Operator scraping configuration

## Platform Helm Values

Location: [`helm/platform-values/`](../helm/platform-values/)

Versioned values for third-party platform charts managed through Argo CD.

Includes values for:

- [`kube-prometheus-stack`](../helm/platform-values/kube-prometheus-stack-values.yaml)
  - Prometheus, Grafana, Alertmanager, and exporters
- [`loki-stack`](../helm/platform-values/loki-values.yaml) - Loki and
  Promtail logging stack
- [`aws-load-balancer-controller`](../helm/platform-values/aws-load-balancer-controller-values-eks.yaml)
  - AWS Application Load Balancer integration for EKS

Separate local and EKS values files are kept where the deployment environments
need different settings.

## GitOps

Location: [`argocd/`](../argocd/)

Argo CD `Application` manifests define the desired Kubernetes state.

The repository includes both local and EKS-oriented application manifests,
including:

- [`document-service`](../argocd/document-service-app.yaml) /
  [`document-service-eks`](../argocd/document-service-app-eks.yaml) - deploys
  the validation service from the internal Helm chart
- [`monitoring`](../argocd/monitoring-app.yaml) /
  [`monitoring-eks`](../argocd/monitoring-app-eks.yaml) - deploys
  kube-prometheus-stack
- [`loki`](../argocd/loki-app.yaml) /
  [`loki-eks`](../argocd/loki-app-eks.yaml) - deploys the logging stack
- [`aws-load-balancer-controller`](../argocd/aws-load-balancer-controller-app-eks.yaml)
  - deploys AWS ingress controller integration for EKS
- [`observability-config`](../argocd/observability-config-app-eks.yaml)
  - provisions Grafana dashboards through GitOps-managed ConfigMaps
- EKS ingress helper manifests for
  [`Grafana`](../argocd/grafana-ingress-eks.yaml),
  [`Argo CD`](../argocd/argocd-ingress-eks.yaml),
  [`Prometheus`](../argocd/prometheus-ingress-eks.yaml), and the
  [`document service`](../argocd/document-service-app-eks.yaml)

## AWS Infrastructure

Location: [`infra/terraform/`](../infra/terraform/)

Terraform configuration for the AWS foundation used by the EKS environment.

Key responsibilities:

- VPC and subnet layout
- EKS cluster
- Managed node group
- IAM resources
- AWS Load Balancer Controller integration
- Public-safe example variables in
  [`terraform.tfvars.example`](../infra/terraform/terraform.tfvars.example)

Local state, plans, backend files, and private variable files are intentionally
ignored by Git.

## EKS Lifecycle Scripts

Location: [`infra/apply/`](../infra/apply/),
[`infra/destroy/`](../infra/destroy/), and
[`infra/script-common.sh`](../infra/script-common.sh)

Operational scripts coordinate the demo environment lifecycle.

Usage and behavior are documented in
[`infra/README.md`](../infra/README.md).

Apply path:

- [`infra/apply/apply-full-stack.sh`](../infra/apply/apply-full-stack.sh)
  - full EKS platform creation and bootstrap flow
- [`infra/apply/apply.sh`](../infra/apply/apply.sh) - Terraform apply wrapper
- [`infra/apply/bootstrap-argocd.sh`](../infra/apply/bootstrap-argocd.sh)
  - Argo CD installation and application bootstrap
- [`infra/apply/prepare-aws-load-balancer-controller.sh`](../infra/apply/prepare-aws-load-balancer-controller.sh)
  - load balancer controller preparation

Destroy path:

- [`infra/destroy/teardown-workloads.sh`](../infra/destroy/teardown-workloads.sh)
  - removes Kubernetes workloads before infrastructure teardown
- [`infra/destroy/cleanup-orphaned-elbs.sh`](../infra/destroy/cleanup-orphaned-elbs.sh)
  - cleans up leftover AWS load balancers
- [`infra/destroy/destroy.sh`](../infra/destroy/destroy.sh) - Terraform
  destroy wrapper

Shared behavior lives in
[`infra/script-common.sh`](../infra/script-common.sh).

## Observability Configuration

Location: [`observability/grafana/`](../observability/grafana/)

Grafana dashboard configuration for the application observability story.

Key files:

- [`dashboards/document-validation-service-observability.json`](../observability/grafana/dashboards/document-validation-service-observability.json)
  - request, rejection, and document-type dashboard
- [`dashboards/Latency.json`](../observability/grafana/dashboards/Latency.json)
  - latency and performance dashboard
- [`Chart.yaml`](../observability/grafana/Chart.yaml) and
  [`templates/dashboard-configmaps.yaml`](../observability/grafana/templates/dashboard-configmaps.yaml)
  - Helm chart that packages dashboard JSON into labeled ConfigMaps for Grafana
  sidecar discovery

## Local Access

Location: [`deploy/local/`](../deploy/local/)

Optional local convenience layer used during the KinD-based project phase.

Includes:

- [`ingress-local.yaml`](../deploy/local/ingress-local.yaml) - local ingress
  manifest
- [`nginx-proxy.conf.tpl`](../deploy/local/nginx-proxy.conf.tpl) - Nginx proxy
  configuration template
- [`scripts/cert-gen.sh`](../deploy/local/scripts/cert-gen.sh) - local
  certificate generation
- [`scripts/proxy-up.sh`](../deploy/local/scripts/proxy-up.sh) and
  [`scripts/proxy-down.sh`](../deploy/local/scripts/proxy-down.sh) - proxy
  start and stop scripts
- [`README.md`](../deploy/local/README.md) - local access documentation

## CI/CD Workflows

Location: [`.github/workflows/`](../.github/workflows/)

GitHub Actions workflows cover application, infrastructure, and documentation
validation.

Main workflow ([`ci.yml`](../.github/workflows/ci.yml)):

- Python formatting and linting
- Unit tests
- Python compile sanity check
- Dependency vulnerability scan
- Dockerfile linting
- Docker build
- Built-container smoke test
- Container vulnerability scan
- GHCR release image publishing
- Helm image tag update for GitOps release

Infrastructure validation
([`infra-validation.yml`](../.github/workflows/infra-validation.yml)):

- Terraform formatting, initialization, validation, linting, and security scanning
- Helm linting and rendering for local and EKS values
- Kubernetes manifest schema validation
- Argo CD manifest validation
- Bash syntax checks and ShellCheck
- Secret scanning

Documentation validation
([`docs-validation.yml`](../.github/workflows/docs-validation.yml)):

- README, docs, infrastructure, and local access link checking
- Documentation-only path triggers

## Documentation

Location: [`docs/`](./)

Project documentation, diagrams, screenshots, and design notes.

Important files:

- [`docs/local-development.md`](local-development.md) - local development
  workflow
- [`docs/design-decisions.md`](design-decisions.md) - design decision record
- [`docs/diagrams/`](diagrams/) - architecture and pipeline diagrams
- [`docs/screenshots/`](screenshots/) - UI, Grafana, and Argo CD screenshots
