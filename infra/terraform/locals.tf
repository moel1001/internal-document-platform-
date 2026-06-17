data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  #use two Availability Zones so EKS nodes and load balancers are not tied to a single data center
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # private subnets host EKS worker nodes. They do not receive direct inbound
  # internet traffic, outbound internet access goes through the NAT gateway.
  private_subnets = [
    for index, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, index)
  ]

  # public subnets host internet-facing infrastructure such as load balancers
  public_subnets = [
    for index, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, index + 100)
  ]

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "internal-document-platform"
  }
}
