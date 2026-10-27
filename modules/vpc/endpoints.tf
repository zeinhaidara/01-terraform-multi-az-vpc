locals {
  gateway_endpoint_services   = ["s3", "dynamodb"]
  interface_endpoint_services = var.enable_interface_endpoints ? ["ecr.api", "ecr.dkr", "sts", "logs"] : []
}

# Gateway endpoints are free. They add a prefix-list route to each route table,
# so S3 and DynamoDB traffic skips the NAT gateway. The public tier is left out
# on purpose: load balancers do not talk to S3 or DynamoDB.
resource "aws_vpc_endpoint" "gateway" {
  for_each = toset(local.gateway_endpoint_services)

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat([for rt in aws_route_table.private : rt.id], [aws_route_table.isolated.id])

  tags = merge(local.tags, { Name = "${local.name}-${each.key}" })
}

resource "aws_security_group" "endpoints" {
  count = var.enable_interface_endpoints ? 1 : 0

  name        = "${local.name}-vpc-endpoints"
  description = "HTTPS from inside the VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${local.name}-vpc-endpoints" })
}

# Endpoint ENIs only receive traffic, so no egress rule is needed.
resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  count = var.enable_interface_endpoints ? 1 : 0

  security_group_id = aws_security_group.endpoints[0].id
  description       = "HTTPS from the VPC CIDR"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443

  tags = local.tags
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.interface_endpoint_services)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true

  tags = merge(local.tags, { Name = "${local.name}-${replace(each.key, ".", "-")}" })
}
