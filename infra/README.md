# Infrastructure Operations Guide

This directory contains the Terraform configuration and lifecycle scripts used
to create and destroy the AWS EKS demo environment for the Internal Document
Platform.

The two main entry points are:

- `infra/apply/apply-full-stack.sh` - creates or reconciles the full EKS demo stack
- `infra/destroy/destroy.sh` - removes the Kubernetes workloads and Terraform-managed AWS infrastructure

These scripts are intended for a production-style portfolio demonstration. They
automate the platform lifecycle, but the environment still creates real AWS
resources such as EKS nodes and Application Load Balancers, so it can generate
AWS charges.

## Prerequisites

Install and configure:

- AWS CLI
- Terraform
- kubectl
- curl
- jq, for orphaned load balancer cleanup during destroy

Authenticate to the AWS account before running the scripts. One common pattern
is to set `AWS_PROFILE` for the command:

```bash
AWS_PROFILE=<profile-name> ./infra/apply/apply-full-stack.sh
```

The scripts read shared settings from `infra/terraform/terraform.tfvars` when it
exists. Start from the public-safe example:

```bash
cp infra/terraform/terraform.tfvars.example infra/terraform/terraform.tfvars
```

Before applying, update at least:

- `aws_region`
- `cluster_endpoint_public_access_cidrs`
- `node_instance_type`

The public API CIDR must include the public IPv4 address of the workstation that
runs the scripts. The example CIDR is only a placeholder.

## Create The Full Stack

Run from the repository root:

```bash
./infra/apply/apply-full-stack.sh
```

With an explicit AWS profile:

```bash
AWS_PROFILE=<profile-name> ./infra/apply/apply-full-stack.sh
```

By default, the full-stack wrapper:

1. Provisions or updates the AWS infrastructure with Terraform.
2. Installs Argo CD into the EKS cluster.
3. Applies the EKS Argo CD applications for the document service, monitoring,
   Loki, AWS Load Balancer Controller, and observability dashboard config.
4. Waits for the expected Argo CD applications to become `Synced` and
   `Healthy`.
5. Waits for the AWS Load Balancer Controller and required Services.
6. Applies browser-facing Ingress manifests for selected platform UIs.
7. Waits for ALB hostnames and verifies HTTP health endpoints.

When the smoke test succeeds, the script prints the discovered URLs for the
document service, Argo CD, Grafana, and Prometheus when those endpoints are
enabled.

## How `apply-full-stack.sh` Works

`apply-full-stack.sh` is a wrapper around smaller scripts:

- `infra/script-common.sh` loads shared defaults, reads `terraform.tfvars`, and
  provides common logging and command checks.
- `infra/apply/apply.sh` runs the Terraform provisioning phase.
- `infra/apply/bootstrap-argocd.sh` installs Argo CD and applies Argo CD
  `Application` manifests.

The Terraform phase performs several guardrails before creating resources:

- Verifies that `terraform.tfvars` exists.
- Refuses to run while the placeholder API allowlist CIDR is still present.
- Optionally checks that the workstation public IPv4 is allowed by
  `cluster_endpoint_public_access_cidrs`.
- Verifies the configured node instance type against AWS free-tier eligibility
  when `FREE_TIER_ONLY=1`.
- Creates a saved Terraform plan before applying it.
- Updates kubeconfig and waits until the EKS API is reachable.

The GitOps phase deliberately applies workload applications before browser
Ingress resources. This allows Argo CD, the workloads, and the AWS Load Balancer
Controller to become healthy before ALBs are requested.

## Useful Apply Options

The scripts can be adjusted with environment variables:

```bash
SKIP_TERRAFORM=1 ./infra/apply/apply-full-stack.sh
```

Use this when the EKS cluster already exists and you only want to re-run the
GitOps bootstrap and exposure flow.

```bash
VERIFY_HTTP_ENDPOINTS=0 ./infra/apply/apply-full-stack.sh
```

Use this when ALB hostnames should be created but HTTP endpoint checks are not
needed.

```bash
WAIT_FOR_INGRESSES=0 ./infra/apply/apply-full-stack.sh
```

Use this to skip the final ingress wait and smoke test.

```bash
EXPOSE_ARGOCD=0 EXPOSE_GRAFANA=0 EXPOSE_PROMETHEUS=0 ./infra/apply/apply-full-stack.sh
```

Use this to keep platform UIs private while still deploying the core stack.

Other useful toggles:

- `INSTALL_MONITORING=0` - skip the monitoring stack and observability config
- `INSTALL_LOKI=0` - skip the logging stack
- `INSTALL_ALB_CONTROLLER=0` - skip AWS Load Balancer Controller installation
- `WAIT_FOR_APPLICATIONS=0` - skip Argo CD application health waits
- `FREE_TIER_ONLY=0` - allow a non-free-tier node type intentionally
- `VERIFY_PUBLIC_IP=0` - skip the public IP preflight check intentionally

## Destroy The Full Stack

Run from the repository root:

```bash
./infra/destroy/destroy.sh
```

With an explicit AWS profile:

```bash
AWS_PROFILE=<profile-name> ./infra/destroy/destroy.sh
```

The destroy flow is intentionally more than a plain `terraform destroy`.
Kubernetes-created AWS resources, especially Application Load Balancers,
network interfaces, and security groups, can block VPC deletion if Terraform
tries to destroy the infrastructure first.

## How `destroy.sh` Works

`destroy.sh` runs this sequence:

1. Initializes Terraform from `infra/terraform/`.
2. Runs `infra/destroy/teardown-workloads.sh`.
3. Runs `infra/destroy/cleanup-orphaned-elbs.sh`.
4. Creates a saved Terraform destroy plan.
5. Applies the saved destroy plan.

`teardown-workloads.sh` connects to EKS while the cluster API is still
available. It deletes Argo CD workload applications, ALB-backed Ingresses, and
LoadBalancer Services, then waits for those Kubernetes resources to disappear.
The AWS Load Balancer Controller application is deleted last so the controller
has time to clean up AWS resources it created.

`cleanup-orphaned-elbs.sh` is a rescue cleanup step. It uses Terraform state to
identify the stack VPC, then deletes only Kubernetes-managed load balancers and
security groups that carry Kubernetes or AWS Load Balancer Controller tags for
this cluster. This prevents leftover controller-managed AWS resources from
blocking Terraform VPC deletion.

Finally, Terraform creates and applies a destroy plan for the infrastructure it
manages directly.

## Useful Destroy Options

```bash
RUN_WORKLOAD_TEARDOWN=0 ./infra/destroy/destroy.sh
```

Skip Kubernetes workload teardown. Use only when the cluster is already
unreachable or the workloads were removed manually.

```bash
RUN_ORPHAN_CLEANUP=0 ./infra/destroy/destroy.sh
```

Skip AWS orphan cleanup. Use only when you know no Kubernetes-managed load
balancer resources remain.

```bash
PLAN_FILE=my-destroy.plan ./infra/destroy/destroy.sh
```

Override the destroy plan filename.

## Verification Commands

Useful commands after apply:

```bash
kubectl get applications -n argocd
kubectl get pods -A
kubectl get ingress -A
kubectl get configmaps -n monitoring -l grafana_dashboard=1
```

Useful checks after destroy:

```bash
aws eks describe-cluster --region <region> --name <cluster-name>
aws elbv2 describe-load-balancers --region <region>
terraform -chdir=infra/terraform state list
```

The EKS `describe-cluster` command should fail after a complete destroy. The
load balancer check is useful when diagnosing resources that might still be
blocking VPC deletion.
