# AWS EKS Deployment Guide

This guide explains how to create, verify, and destroy the AWS EKS demo
environment for the Internal Document Platform.

The EKS path is the cloud portfolio deployment. It provisions AWS
infrastructure with Terraform, installs Argo CD, reconciles the platform
applications through GitOps, exposes selected services through AWS Application
Load Balancers, and verifies the running stack.

## Cost Warning

This guide creates real AWS resources, including EKS worker nodes and
Application Load Balancers. These resources can generate AWS charges while they
exist.

Always run the destroy flow when you finish testing:

```bash
AWS_PROFILE=<profile-name> ./infra/destroy/destroy.sh
```

## Quickstart

From the repository root:

```bash
cp infra/terraform/terraform.tfvars.example infra/terraform/terraform.tfvars
```

Edit `infra/terraform/terraform.tfvars`, then create the stack:

```bash
AWS_PROFILE=<profile-name> ./infra/apply/apply-full-stack.sh
```

When testing is complete:

```bash
AWS_PROFILE=<profile-name> ./infra/destroy/destroy.sh
```

## Prerequisites

Install and configure:

- AWS CLI
- Terraform
- kubectl
- curl
- jq

Authenticate to AWS before running the scripts. One common pattern is to pass
an explicit profile:

```bash
AWS_PROFILE=<profile-name> aws sts get-caller-identity
```

## Configure Terraform Variables

Create a local variables file from the public-safe example:

```bash
cp infra/terraform/terraform.tfvars.example infra/terraform/terraform.tfvars
```

Update at least:

- `aws_region`
- `cluster_endpoint_public_access_cidrs`
- `node_instance_type`

The Kubernetes API CIDR must include the public IPv4 address of the workstation
running the deployment scripts. The example CIDR is only a placeholder and
should not be used directly.

## Create The Full Stack

Run from the repository root:

```bash
AWS_PROFILE=<profile-name> ./infra/apply/apply-full-stack.sh
```

The script coordinates the full demo lifecycle:

1. Provision or update AWS infrastructure with Terraform.
2. Install Argo CD into EKS.
3. Apply the EKS Argo CD applications.
4. Wait for the expected applications to become `Synced` and `Healthy`.
5. Wait for the AWS Load Balancer Controller and required services.
6. Apply browser-facing Ingress manifests.
7. Wait for ALB hostnames and run HTTP smoke checks.

When the smoke checks succeed, the script prints the discovered URLs for the
document service, Argo CD, Grafana, and Prometheus when those endpoints are
enabled.

## GitOps Applications

The EKS environment is reconciled through these Argo CD applications:

- `document-service-eks`
- `monitoring-eks`
- `loki-eks`
- `observability-config-eks`
- `aws-load-balancer-controller-eks`

Useful verification command:

```bash
kubectl get applications -n argocd
```

All expected applications should become `Synced` and `Healthy`.

## Observability Verification

Check the platform pods:

```bash
kubectl get pods -A
```

Check Grafana dashboard ConfigMaps:

```bash
kubectl get configmaps -n monitoring -l grafana_dashboard=1
```

Check Loki and Promtail:

```bash
kubectl get pods -n logging
```

In EKS, Grafana uses the Loki datasource URL:

```text
http://loki-eks.logging:3100
```

The Grafana datasource UID is provisioned as:

```text
loki
```

## Generate Traffic

Use the document-service `/ui` page or send requests to the service endpoint
printed by `apply-full-stack.sh`.

Example request:

```bash
curl -fsS -X POST http://<document-service-alb>/validate \
  -H 'Content-Type: application/json' \
  -d '{"document_id":"INV-001","document_type":"invoice","created_at":"2025-01-10","source_system":"erp"}'
```

Fresh traffic makes the Prometheus dashboards and Loki log panels easier to
verify.

## Reconcile Without Recreating Terraform

If the AWS infrastructure already exists and you only want to re-run GitOps
bootstrap, ingress exposure, and smoke checks:

```bash
SKIP_TERRAFORM=1 INSTALL_ARGOCD=0 AWS_PROFILE=<profile-name> ./infra/apply/apply-full-stack.sh
```

## Recover EKS Access After A Public IP Change

The EKS API endpoint is restricted by
`cluster_endpoint_public_access_cidrs` in the local
`infra/terraform/terraform.tfvars` file. Changing networks, locations, mobile
hotspots, or VPN endpoints can change the workstation's public IPv4 address.
When that happens, the cluster and workloads continue running, but `kubectl`
may time out because the new address is not in the API allowlist.

Do not destroy or rebuild the stack. Update only the EKS API allowlist.

First, discover the current public IPv4 address:

```bash
# [READ-ONLY]
curl -4 https://checkip.amazonaws.com
```

Replace the old `/32` entry in `infra/terraform/terraform.tfvars` with the new
address:

```hcl
cluster_endpoint_public_access_cidrs = [
  "<current-public-ip>/32"
]
```

Create a saved, targeted recovery plan:

```bash
# [READ-ONLY] [LOCAL WRITE]
AWS_PROFILE=<profile-name> terraform -chdir=infra/terraform plan \
  -target='module.eks.aws_eks_cluster.this[0]' \
  -out=ip-access.tfplan
```

Resource targeting is not intended for routine Terraform operations. It is
used here as a narrow recovery measure so an EKS API allowlist change is not
combined with unrelated provider-derived changes, such as add-on version or
OIDC thumbprint recalculation.

The expected summary is:

```text
Plan: 0 to add, 1 to change, 0 to destroy.
```

Inspect the saved plan before applying it:

```bash
# [READ-ONLY]
terraform -chdir=infra/terraform show ip-access.tfplan
```

Confirm that:

- `module.eks.aws_eks_cluster.this[0]` is the only resource being changed.
- The resource will be updated in place.
- The old CIDR is removed and the new CIDR is added.
- No resource will be added, replaced, or destroyed.

Apply the exact reviewed plan:

```bash
# [AWS CHANGE]
AWS_PROFILE=<profile-name> terraform -chdir=infra/terraform apply ip-access.tfplan
```

After AWS completes the endpoint update, verify access and workload health:

```bash
# [READ-ONLY]
kubectl get nodes
kubectl get pods --all-namespaces
```

Do not use `0.0.0.0/0` as a convenience allowlist. Keep access restricted to
the operator's current `/32` address. Before running the destroy workflow,
verify that the current public IP is allowed because teardown must reach the
Kubernetes API to remove Ingress resources and their AWS load balancers
cleanly.

## Destroy The Full Stack

Run from the repository root:

```bash
AWS_PROFILE=<profile-name> ./infra/destroy/destroy.sh
```

The destroy flow removes Kubernetes-managed AWS resources before Terraform
destroys the infrastructure. This helps prevent ALBs, network interfaces, and
security groups from blocking VPC deletion.

Useful checks after destroy:

```bash
aws eks describe-cluster --region <region> --name <cluster-name>
aws elbv2 describe-load-balancers --region <region>
terraform -chdir=infra/terraform state list
```

The EKS cluster lookup should fail after a complete destroy.

## More Detail

See the [Infrastructure Operations Guide](../infra/README.md) for the full
script behavior, environment variables, skip flags, and recovery options.
