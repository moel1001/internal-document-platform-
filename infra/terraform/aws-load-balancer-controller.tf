locals {
  aws_load_balancer_controller_namespace            = "kube-system"
  aws_load_balancer_controller_service_account_name = "aws-load-balancer-controller"
  aws_load_balancer_controller_policy_name          = "AWSLoadBalancerControllerIAMPolicy"
  aws_load_balancer_controller_role_name            = "AmazonEKSLoadBalancerControllerRole"
}

# Permissions the AWS Load Balancer Controller needs to manage AWS load balancers.
resource "aws_iam_policy" "aws_load_balancer_controller" {
  name        = local.aws_load_balancer_controller_policy_name
  description = "Permissions for the AWS Load Balancer Controller running in EKS."
  policy      = file("${path.module}/aws-load-balancer-controller-iam-policy.json")

  tags = local.common_tags
}

# trust policy allowing only the controller's Kubernetes service account to use the role
data "aws_iam_policy_document" "aws_load_balancer_controller_assume_role" {
  statement {
    sid     = "AllowEksServiceAccountToAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values = [
        "system:serviceaccount:${local.aws_load_balancer_controller_namespace}:${local.aws_load_balancer_controller_service_account_name}",
      ]
    }
  }
}

# IAM role that the controller service account assumes through IRSA
resource "aws_iam_role" "aws_load_balancer_controller" {
  name               = local.aws_load_balancer_controller_role_name
  assume_role_policy = data.aws_iam_policy_document.aws_load_balancer_controller_assume_role.json

  tags = local.common_tags
}

# Attach the controller permissions to the IRSA role
resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
  role       = aws_iam_role.aws_load_balancer_controller.name
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
}
