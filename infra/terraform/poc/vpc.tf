# VPC with public + private subnets across two AZs.
# Single NAT gateway to keep the POC cheap (~$32/mo instead of one-per-AZ).
# Nodes and RDS live in private subnets; the NAT lets nodes pull images and
# reach AWS APIs. Public subnets exist for the (optional) internet-facing LBs.

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "${local.name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = [cidrsubnet(var.vpc_cidr, 4, 0), cidrsubnet(var.vpc_cidr, 4, 1)]
  public_subnets  = [cidrsubnet(var.vpc_cidr, 4, 2), cidrsubnet(var.vpc_cidr, 4, 3)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags EKS uses to auto-discover subnets for load balancers.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = local.common_tags
}
