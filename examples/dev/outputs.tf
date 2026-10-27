output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "isolated_subnet_ids" {
  value = module.vpc.isolated_subnet_ids
}

output "nat_gateway_ids" {
  value = module.vpc.nat_gateway_ids
}

output "gateway_endpoint_ids" {
  value = module.vpc.gateway_endpoint_ids
}

output "interface_endpoint_ids" {
  value = module.vpc.interface_endpoint_ids
}
