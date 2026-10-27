data "aws_availability_zones" "available" {
  #checkov:skip=CKV_AWS_394:Only the first az_count sorted names are used, so a newly added AZ does not change the result.
  state = "available"

  # Skip Local Zones and Wavelength Zones, which need opt-in and lack some services.
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }

  lifecycle {
    postcondition {
      condition     = length(self.names) >= var.az_count
      error_message = "Region ${var.region} has only ${length(self.names)} usable availability zones, but az_count is ${var.az_count}."
    }
  }
}

locals {
  name = "${var.project}-${var.environment}"

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project
    ManagedBy   = "terraform"
  })

  # Sorted so the same AZs are picked on every run.
  azs      = slice(sort(data.aws_availability_zones.available.names), 0, var.az_count)
  az_index = { for i, az in local.azs : az => i }

  # The VPC CIDR is cut into 16 equal blocks (4 extra bits). Each tier owns a
  # block of 4 slots, one per possible AZ, so the layout does not change when
  # az_count goes from 2 to 3. Slots 12-15 are left free for a future tier.
  subnet_newbits = 4
  tier_offset = {
    public   = 0
    private  = 4
    isolated = 8
  }
  subnet_cidrs = {
    for tier, offset in local.tier_offset : tier => {
      for az, i in local.az_index : az => cidrsubnet(var.vpc_cidr, local.subnet_newbits, offset + i)
    }
  }

  nat_strategy = var.nat_strategy == "auto" ? (var.environment == "prod" ? "per_az" : "single") : var.nat_strategy
  nat_azs      = local.nat_strategy == "per_az" ? local.azs : slice(local.azs, 0, 1)
  # Which NAT gateway each AZ sends its traffic to.
  nat_for_az = { for az in local.azs : az => local.nat_strategy == "per_az" ? az : local.azs[0] }
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = local.name })
}

# Close the default security group so nothing can use it by accident.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${local.name}-default-closed" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = local.name })
}

resource "aws_subnet" "public" {
  for_each = local.subnet_cidrs.public

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name = "${local.name}-public-${each.key}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  for_each = local.subnet_cidrs.private

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = merge(local.tags, {
    Name = "${local.name}-private-${each.key}"
    Tier = "private"
  })
}

resource "aws_subnet" "isolated" {
  for_each = local.subnet_cidrs.isolated

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = merge(local.tags, {
    Name = "${local.name}-isolated-${each.key}"
    Tier = "isolated"
  })
}

# Public: one route table, default route to the internet gateway.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${local.name}-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Private: one route table per AZ so each AZ can use its own NAT gateway.
resource "aws_route_table" "private" {
  for_each = aws_subnet.private

  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${local.name}-private-${each.key}" })
}

resource "aws_route" "private_nat" {
  for_each = aws_route_table.private

  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[local.nat_for_az[each.key]].id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

# Isolated: one route table with only the implicit local route. No aws_route
# resource is ever attached to it, and gateway endpoints add prefix-list routes.
resource "aws_route_table" "isolated" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${local.name}-isolated" })
}

resource "aws_route_table_association" "isolated" {
  for_each = aws_subnet.isolated

  subnet_id      = each.value.id
  route_table_id = aws_route_table.isolated.id
}
