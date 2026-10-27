output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "availability_zones" {
  description = "Availability zones in use, in order."
  value       = local.azs
}

output "public_subnet_ids" {
  description = "Public subnet IDs keyed by availability zone."
  value       = { for az, s in aws_subnet.public : az => s.id }
}

output "private_subnet_ids" {
  description = "Private (application) subnet IDs keyed by availability zone."
  value       = { for az, s in aws_subnet.private : az => s.id }
}

output "isolated_subnet_ids" {
  description = "Isolated (database) subnet IDs keyed by availability zone."
  value       = { for az, s in aws_subnet.isolated : az => s.id }
}

output "subnet_cidrs" {
  description = "Subnet CIDRs by tier, then availability zone."
  value       = local.subnet_cidrs
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs keyed by the availability zone they sit in."
  value       = { for az, n in aws_nat_gateway.this : az => n.id }
}

output "nat_strategy" {
  description = "NAT strategy in effect after resolving \"auto\"."
  value       = local.nat_strategy
}

output "route_table_ids" {
  description = "Route table IDs. Private route tables are keyed by availability zone."
  value = {
    public   = aws_route_table.public.id
    private  = { for az, rt in aws_route_table.private : az => rt.id }
    isolated = aws_route_table.isolated.id
  }
}

output "gateway_endpoint_ids" {
  description = "Gateway endpoint IDs keyed by service (s3, dynamodb)."
  value       = { for k, e in aws_vpc_endpoint.gateway : k => e.id }
}

output "interface_endpoint_ids" {
  description = "Interface endpoint IDs keyed by service (ecr.api, ecr.dkr, sts, logs)."
  value       = { for k, e in aws_vpc_endpoint.interface : k => e.id }
}

output "endpoint_security_group_id" {
  description = "Security group on the interface endpoints, or null when they are disabled."
  value       = one(aws_security_group.endpoints[*].id)
}

output "flow_log_group_name" {
  description = "CloudWatch Logs group that receives the VPC flow logs."
  value       = aws_cloudwatch_log_group.flow_logs.name
}
