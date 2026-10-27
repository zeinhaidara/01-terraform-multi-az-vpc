# Prod: three AZs, one NAT gateway per AZ, one year of flow logs.
provider "aws" {
  region = var.region
}

module "vpc" {
  source = "../../modules/vpc"

  region                  = var.region
  environment             = "prod"
  project                 = "three-tier"
  vpc_cidr                = var.vpc_cidr
  az_count                = var.az_count
  nat_strategy            = var.nat_strategy
  flow_log_retention_days = var.flow_log_retention_days
  tags                    = var.tags
}
