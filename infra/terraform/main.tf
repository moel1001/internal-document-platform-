# This Terraform root only provisions AWS infrastructure.
# Application deployment remains in Helm/Argo CD so the local kind workflow stays untouched.

# creates the AWS network foundation for EKS: a VPC spread across public and
# private subnets, NAT for private outbound traffic, DNS support, and subnet
# tags that let Kubernetes place AWS load balancers correctly.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  enable_nat_gateway = true

  # use one NAT gateway to keep this demo environment cheaper, instead of one NAT Gateway per AZ
  single_nat_gateway = true

  # EKS and AWS integration expect VPC DNS hostnames and name resolution to work
  enable_dns_hostnames = true
  enable_dns_support   = true

  # These tags let Kubernetes discover where to place AWS load balancers:
  # public subnets for internet-facing load balancers, private subnets for
  # internal load balancers. "shared" marks the subnets as available to this
  # cluster without making Kubernetes the exclusive owner.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  tags = local.common_tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.23"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Use standard Kubernetes version support to avoid extended-support charges
  cluster_upgrade_policy = {
    support_type = "STANDARD"
  }

  # allow kubectl access from approved public CIDRs while keeping private API
  # access available from inside the VPC.
  cluster_endpoint_public_access       = true
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Give the IAM identity running Terraform admin access to the new cluster
  enable_cluster_creator_admin_permissions = true

  # Let Kubernetes service accounts assume specific AWS IAM roles
  enable_irsa = true

  # Install the core EKS networking and DNS addons managed by AWS
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }
  # Keep control plane logging out of this demo stack to reduce AWS cost
  create_cloudwatch_log_group = false

  # Run worker nodes in private subnets. Public subnets are reserved for load
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_group_defaults = {
    ami_type       = "AL2023_x86_64_STANDARD"
    disk_size      = var.node_disk_size_gb
    instance_types = [var.node_instance_type]

    tags = local.common_tags
  }

  #start with one on-demand worker node and allow limited scale-out for demos
  eks_managed_node_groups = {
    default = {
      min_size     = var.node_group_min_size
      desired_size = var.node_group_desired_size
      max_size     = var.node_group_max_size

      capacity_type = "ON_DEMAND"
    }
  }

  tags = local.common_tags
}
