variable "aws_region" {
  description = "AWS region where the EKS environment will be created."
  type        = string
}

variable "project_name" {
  description = "High-level project name used in resource naming and tagging."
  type        = string
  default     = "internal-document-platform"
}

variable "environment" {
  description = "Short environment label for tags and resource names."
  type        = string
  default     = "portfolio"
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "idp-eks"
}

variable "cluster_version" {
  description = "EKS Kubernetes version. Keep this on a version under standard support to avoid extended-support charges."
  type        = string
  default     = "1.33"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. The default 10.0.0.0/16 gives the cluster a large private IPv4 range to split into subnets."
  type        = string
  default     = "10.0.0.0/16"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public EKS API endpoint."
  type        = list(string)
  default     = ["203.0.113.10/32"]
}

variable "node_instance_type" {
  description = "EC2 instance type for the managed node group."
  type        = string
  default     = "m7i-flex.large"
}

variable "node_disk_size_gb" {
  description = "Root EBS volume size in GiB for each worker node."
  type        = number
  default     = 30
}

variable "node_group_min_size" {
  description = "Minimum number of nodes in the managed node group."
  type        = number
  default     = 1
}

variable "node_group_desired_size" {
  description = "Desired number of nodes in the managed node group."
  type        = number
  default     = 1
}

variable "node_group_max_size" {
  description = "Maximum number of nodes in the managed node group."
  type        = number
  default     = 2
}
