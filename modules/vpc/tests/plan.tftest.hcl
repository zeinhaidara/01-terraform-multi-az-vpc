# Plan-only tests. The AWS provider is mocked, so no credentials or network
# access are needed and nothing is ever created.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d"]
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
}

variables {
  region      = "us-east-1"
  environment = "dev"
  vpc_cidr    = "10.0.0.0/16"
  az_count    = 3
}

run "three_azs_give_nine_subnets" {
  command = plan

  assert {
    condition     = length(aws_subnet.public) == 3 && length(aws_subnet.private) == 3 && length(aws_subnet.isolated) == 3
    error_message = "Expected 3 subnets per tier with az_count = 3."
  }

  assert {
    condition     = length(output.availability_zones) == 3
    error_message = "Expected 3 availability zones."
  }
}

run "two_azs_give_six_subnets" {
  command = plan

  variables {
    az_count = 2
  }

  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_subnet.private) == 2 && length(aws_subnet.isolated) == 2
    error_message = "Expected 2 subnets per tier with az_count = 2."
  }
}

# Route table IDs are only known after apply, so they are pinned during plan.
# That lets the test see which table each aws_route is wired to.
run "isolated_tier_has_no_default_route" {
  command = plan

  override_resource {
    target          = aws_route_table.public
    override_during = plan
    values          = { id = "rtb-public" }
  }

  override_resource {
    target          = aws_route_table.private
    override_during = plan
    values          = { id = "rtb-private" }
  }

  override_resource {
    target          = aws_route_table.isolated
    override_during = plan
    values          = { id = "rtb-isolated" }
  }

  assert {
    condition     = aws_route.public_internet.route_table_id == "rtb-public"
    error_message = "The internet route must be attached to the public route table."
  }

  assert {
    condition     = length(aws_route.private_nat) == 3 && alltrue([for r in values(aws_route.private_nat) : r.route_table_id == "rtb-private"])
    error_message = "NAT routes must be attached to the private route tables only."
  }

  # Every aws_route in the module is one of the two above, so none can
  # point at the isolated table.
  assert {
    condition     = !contains(concat([aws_route.public_internet.route_table_id], [for r in values(aws_route.private_nat) : r.route_table_id]), "rtb-isolated")
    error_message = "The isolated route table must have no default route."
  }

  assert {
    condition     = alltrue([for r in values(aws_route_table_association.isolated) : r.route_table_id == "rtb-isolated"]) && length(aws_route_table_association.isolated) == 3
    error_message = "Every isolated subnet must use the isolated route table."
  }

  assert {
    condition     = contains(aws_vpc_endpoint.gateway["dynamodb"].route_table_ids, "rtb-isolated") && !contains(aws_vpc_endpoint.gateway["dynamodb"].route_table_ids, "rtb-public")
    error_message = "Gateway endpoints go on the private and isolated tables, not the public one."
  }
}

run "per_az_strategy_gives_one_nat_per_az" {
  command = plan

  variables {
    nat_strategy = "per_az"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 3 && length(aws_eip.nat) == 3
    error_message = "per_az with 3 AZs must create 3 NAT gateways and 3 EIPs."
  }
}

run "single_strategy_gives_one_nat" {
  command = plan

  variables {
    environment  = "prod"
    nat_strategy = "single"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "single must create exactly one NAT gateway, even in prod."
  }

  assert {
    condition     = length(aws_route.private_nat) == 3
    error_message = "All 3 private route tables must still have a default route."
  }
}

run "auto_strategy_is_single_in_dev" {
  command = plan

  assert {
    condition     = length(aws_nat_gateway.this) == 1 && output.nat_strategy == "single"
    error_message = "auto in dev must resolve to a single shared NAT gateway."
  }
}

run "auto_strategy_is_single_in_stage" {
  command = plan

  variables {
    environment = "stage"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "auto in stage must resolve to a single shared NAT gateway."
  }
}

run "auto_strategy_is_per_az_in_prod" {
  command = plan

  variables {
    environment = "prod"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 3 && output.nat_strategy == "per_az"
    error_message = "auto in prod must resolve to one NAT gateway per AZ."
  }
}

# CIDR blocks of the same size are aligned, so two of them either match or do
# not overlap at all. Same prefix length plus all distinct means no overlap.
run "subnets_do_not_overlap_in_a_slash_16" {
  command = plan

  assert {
    condition     = length(distinct(flatten([for t in values(output.subnet_cidrs) : values(t)]))) == 9
    error_message = "Expected 9 distinct subnet CIDRs."
  }

  assert {
    condition     = length(distinct([for c in flatten([for t in values(output.subnet_cidrs) : values(t)]) : split("/", c)[1]])) == 1
    error_message = "All subnets must have the same prefix length."
  }

  # Masking a subnet address with the VPC prefix must give the VPC network.
  assert {
    condition = alltrue([
      for c in flatten([for t in values(output.subnet_cidrs) : values(t)]) :
      cidrhost("${cidrhost(c, 0)}/${split("/", var.vpc_cidr)[1]}", 0) == cidrhost(var.vpc_cidr, 0)
    ])
    error_message = "A subnet falls outside the VPC CIDR."
  }
}

run "smallest_vpc_still_fits_all_subnets" {
  command = plan

  variables {
    vpc_cidr = "192.168.7.0/24"
    az_count = 2
  }

  assert {
    condition     = length(distinct(flatten([for t in values(output.subnet_cidrs) : values(t)]))) == 6
    error_message = "Expected 6 distinct subnet CIDRs in a /24."
  }

  assert {
    condition     = alltrue([for c in flatten([for t in values(output.subnet_cidrs) : values(t)]) : endswith(c, "/28")])
    error_message = "A /24 split into 16 blocks must give /28 subnets."
  }
}

run "subnet_layout_is_stable_when_az_count_grows" {
  command = plan

  variables {
    az_count = 2
  }

  assert {
    condition = (
      output.subnet_cidrs.public["us-east-1a"] == "10.0.0.0/20" &&
      output.subnet_cidrs.private["us-east-1a"] == "10.0.64.0/20" &&
      output.subnet_cidrs.isolated["us-east-1b"] == "10.0.144.0/20"
    )
    error_message = "Slots are fixed per tier and AZ index, so these CIDRs must not depend on az_count."
  }
}

run "endpoints_and_security_group" {
  command = plan

  assert {
    condition     = length(aws_vpc_endpoint.gateway) == 2 && toset(keys(aws_vpc_endpoint.gateway)) == toset(["s3", "dynamodb"])
    error_message = "Expected gateway endpoints for s3 and dynamodb."
  }

  assert {
    condition     = toset(keys(aws_vpc_endpoint.interface)) == toset(["ecr.api", "ecr.dkr", "sts", "logs"])
    error_message = "Expected interface endpoints for ecr.api, ecr.dkr, sts and logs."
  }

  assert {
    condition     = alltrue([for e in values(aws_vpc_endpoint.interface) : e.private_dns_enabled])
    error_message = "Interface endpoints need private DNS enabled."
  }

  assert {
    condition = (
      aws_vpc_security_group_ingress_rule.endpoints_https[0].from_port == 443 &&
      aws_vpc_security_group_ingress_rule.endpoints_https[0].to_port == 443 &&
      aws_vpc_security_group_ingress_rule.endpoints_https[0].cidr_ipv4 == "10.0.0.0/16"
    )
    error_message = "The endpoint security group must allow only 443 from the VPC CIDR."
  }
}

run "interface_endpoints_can_be_turned_off" {
  command = plan

  variables {
    enable_interface_endpoints = false
  }

  assert {
    condition     = length(aws_vpc_endpoint.interface) == 0 && length(aws_security_group.endpoints) == 0
    error_message = "No interface endpoints or endpoint security group expected when disabled."
  }

  assert {
    condition     = length(aws_vpc_endpoint.gateway) == 2
    error_message = "Gateway endpoints are free and stay on."
  }
}

run "flow_logs_and_retention" {
  command = plan

  variables {
    flow_log_retention_days = 90
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_logs.retention_in_days == 90
    error_message = "Retention must follow flow_log_retention_days."
  }

  assert {
    condition     = aws_flow_log.this.traffic_type == "ALL" && aws_flow_log.this.log_destination_type == "cloud-watch-logs"
    error_message = "Flow logs must capture ALL traffic to CloudWatch Logs."
  }
}

run "required_tags_cannot_be_overridden" {
  command = plan

  variables {
    environment = "prod"
    tags = {
      Environment = "something-else"
      Owner       = "platform-team"
    }
  }

  assert {
    condition = (
      aws_vpc.this.tags["Environment"] == "prod" &&
      aws_vpc.this.tags["ManagedBy"] == "terraform" &&
      aws_vpc.this.tags["Owner"] == "platform-team"
    )
    error_message = "Environment and ManagedBy are fixed, and extra tags must be merged in."
  }
}
