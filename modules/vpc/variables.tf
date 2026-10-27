variable "region" {
  description = "AWS region the VPC is built in. Used to build VPC endpoint service names."
  type        = string
}

variable "environment" {
  description = "Deployment environment. Drives the default NAT strategy."
  type        = string

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be one of: dev, stage, prod."
  }
}

variable "project" {
  description = "Project name, used in resource names and the Project tag."
  type        = string
  default     = "three-tier"
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC. Must be between /16 and /24."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition = (
      can(cidrhost(var.vpc_cidr, 0)) &&
      tonumber(split("/", var.vpc_cidr)[1]) >= 16 &&
      tonumber(split("/", var.vpc_cidr)[1]) <= 24
    )
    error_message = "vpc_cidr must be a valid IPv4 CIDR with a prefix length from /16 to /24."
  }
}

variable "az_count" {
  description = "Number of availability zones to use (2 or 3)."
  type        = number
  default     = 3

  validation {
    condition     = contains([2, 3], var.az_count)
    error_message = "az_count must be 2 or 3."
  }
}

variable "nat_strategy" {
  description = <<-EOT
    NAT gateway layout. "per_az" creates one NAT gateway in every AZ, "single"
    creates one shared NAT gateway, and "auto" picks per_az for prod and single
    for dev and stage.
  EOT
  type        = string
  default     = "auto"

  validation {
    condition     = contains(["auto", "per_az", "single"], var.nat_strategy)
    error_message = "nat_strategy must be one of: auto, per_az, single."
  }
}

variable "enable_interface_endpoints" {
  description = "Create the ecr.api, ecr.dkr, sts and logs interface endpoints."
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "Retention of the VPC flow log group in days. Must be a value CloudWatch Logs accepts."
  type        = number
  default     = 30

  validation {
    condition = contains(
      [1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653],
      var.flow_log_retention_days
    )
    error_message = "flow_log_retention_days must be a retention value supported by CloudWatch Logs, for example 14, 30, 90 or 365."
  }
}

variable "tags" {
  description = "Extra tags merged onto every resource. Environment, Project and ManagedBy always win."
  type        = map(string)
  default     = {}
}
