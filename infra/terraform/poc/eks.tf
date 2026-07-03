# EKS cluster + a single managed node group (2x t3.medium by default).
#
# v20 of this module uses EKS "access entries" instead of the old aws-auth
# ConfigMap. `enable_cluster_creator_admin_permissions = true` grants the IAM
# principal running `terraform apply` cluster-admin, so kubectl works right away.
#
# The module creates the IAM OIDC provider for the cluster, which is what makes
# IRSA (IAM Roles for Service Accounts) possible — see irsa.tf.

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = local.name
  cluster_version = var.kubernetes_version

  # Public endpoint so we can kubectl/helm from a laptop. Private-only would
  # require a bastion or VPN; not worth it for a POC.
  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  # Core add-ons managed by EKS. No EBS CSI driver: Temporal uses external RDS,
  # so the cluster needs no persistent volumes.
  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]
      min_size       = 1
      max_size       = 3
      desired_size   = var.node_desired_size
      capacity_type  = "ON_DEMAND"
    }
  }

  tags = local.common_tags
}
