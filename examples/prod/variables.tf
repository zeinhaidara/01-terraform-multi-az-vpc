variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR, between /16 and /24."
  type        = string
  default     = "10.20.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones (2 or 3)."
  type        = number
  default     = 3
}

variable "nat_strategy" {
  description = "auto, per_az or single. auto means per_az for prod and single otherwise."
  type        = string
  default     = "auto"
}

variable "flow_log_retention_days" {
  description = "Retention of the flow log group in days."
  type        = number
  default     = 365
}

variable "tags" {
  description = "Extra tags for every resource."
  type        = map(string)
  default     = {}
}
