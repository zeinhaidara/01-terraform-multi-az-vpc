# Input validation tests. Each run must be rejected.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }
}

variables {
  region      = "us-east-1"
  environment = "dev"
}

run "vpc_cidr_larger_than_slash_16_is_rejected" {
  command = plan

  variables {
    vpc_cidr = "10.0.0.0/15"
  }

  expect_failures = [var.vpc_cidr]
}

run "vpc_cidr_smaller_than_slash_24_is_rejected" {
  command = plan

  variables {
    vpc_cidr = "10.0.0.0/25"
  }

  expect_failures = [var.vpc_cidr]
}

run "vpc_cidr_that_is_not_a_cidr_is_rejected" {
  command = plan

  variables {
    vpc_cidr = "not-a-cidr"
  }

  expect_failures = [var.vpc_cidr]
}

run "unknown_environment_is_rejected" {
  command = plan

  variables {
    environment = "qa"
  }

  expect_failures = [var.environment]
}

run "az_count_of_four_is_rejected" {
  command = plan

  variables {
    az_count = 4
  }

  expect_failures = [var.az_count]
}

run "unknown_nat_strategy_is_rejected" {
  command = plan

  variables {
    nat_strategy = "two"
  }

  expect_failures = [var.nat_strategy]
}

run "unsupported_retention_is_rejected" {
  command = plan

  variables {
    flow_log_retention_days = 10
  }

  expect_failures = [var.flow_log_retention_days]
}

run "region_with_too_few_azs_is_rejected" {
  command = plan

  variables {
    az_count = 3
  }

  override_data {
    target = data.aws_availability_zones.available
    values = {
      names = ["us-east-1a", "us-east-1b"]
    }
  }

  expect_failures = [data.aws_availability_zones.available]
}
