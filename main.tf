# Create custom vpc for Vault and Consul cluster
module "custom_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "vault-phoenixveritas-custom-vpc"
  cidr = "11.0.0.0/16"

  azs             = ["us-east-2a", "us-east-2b", "us-east-2c"]
  private_subnets = ["11.0.1.0/24", "11.0.2.0/24", "11.0.3.0/24"]
  public_subnets  = ["11.0.101.0/24", "11.0.102.0/24", "11.0.103.0/24"]

  enable_nat_gateway = false
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true
}

# Configure the Vault cluster to use the ELB
module "vault_cluster" {
  source = "github.com/hashicorp/terraform-aws-vault//modules/vault-cluster?ref=v0.16.0"

  cluster_name  = var.vault_cluster_name
  cluster_size  = var.vault_cluster_size
  instance_type = var.vault_instance_type
  ami_id        = var.ami_id
  user_data     = data.template_file.user_data_vault_cluster.rendered

  vpc_id     = module.custom_vpc.vpc_id
  subnet_ids = module.custom_vpc.public_subnets

  enable_auto_unseal = true

  auto_unseal_kms_key_arn = data.aws_kms_alias.vault-kms-alias-key.target_key_arn

  allowed_ssh_cidr_blocks              = ["0.0.0.0/0"]
  allowed_inbound_cidr_blocks          = ["0.0.0.0/0"]
  allowed_inbound_security_group_ids   = []
  allowed_inbound_security_group_count = 0
  ssh_key_name                         = var.ssh_key_name
}

# Attach IAM policies for Consul
module "consul_iam_policies_servers" {
  source = "github.com/hashicorp/terraform-aws-consul.git//modules/consul-iam-policies?ref=v0.10.1"

  iam_role_id = module.vault_cluster.iam_role_id
}

# Permit Consul specific traffic in Vault Cluster
module "security_group_rules" {
  source = "github.com/hashicorp/terraform-aws-consul.git//modules/consul-client-security-group-rules?ref=v0.10.1"

  security_group_id = module.vault_cluster.security_group_id

  allowed_inbound_cidr_blocks = ["0.0.0.0/0"]
}

# Configure the Consul cluster
module "consul_cluster" {
  source = "github.com/hashicorp/terraform-aws-consul//modules/consul-cluster?ref=v0.10.1"

  cluster_name      = var.consul_cluster_name
  cluster_size      = var.consul_cluster_size
  instance_type     = var.consul_instance_type
  cluster_tag_key   = var.consul_cluster_tag_key
  cluster_tag_value = var.consul_cluster_name

  ami_id    = var.ami_id
  user_data = data.template_file.user_data_consul.rendered

  vpc_id     = module.custom_vpc.vpc_id
  subnet_ids = module.custom_vpc.public_subnets

  allowed_ssh_cidr_blocks     = ["0.0.0.0/0"]
  allowed_inbound_cidr_blocks = ["0.0.0.0/0"]
  ssh_key_name                = var.ssh_key_name
}

data "aws_kms_alias" "vault-kms-alias-key" {
  name = "alias/${var.auto_unseal_kms_key_alias}"
}

data "template_file" "user_data_vault_cluster" {
  template = file("${path.module}/user-data-vault.sh")

  vars = {
    consul_cluster_tag_key   = var.consul_cluster_tag_key
    consul_cluster_tag_value = var.consul_cluster_name
    kms_key_id               = data.aws_kms_alias.vault-kms-alias-key.target_key_id
    aws_region               = data.aws_region.current.name
  }
}

data "template_file" "user_data_consul" {
  template = file("${path.module}/user-data-consul.sh")

  vars = {
    consul_cluster_tag_key   = var.consul_cluster_tag_key
    consul_cluster_tag_value = var.consul_cluster_name
  }
}

data "aws_region" "current" {
}
