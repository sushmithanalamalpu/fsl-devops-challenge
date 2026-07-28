variable "project_name" {
  description = "Project name used in AWS resource names."
  type        = string
  default     = "rdicidr"
}

variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["devel", "stage"], var.environment)
    error_message = "Environment must be either devel or stage."
  }
}

variable "aws_region" {
  description = "AWS region for S3 and related resources."
  type        = string
  default     = "us-east-1"
}

variable "log_retention_days" {
  description = "Number of days to retain CloudFront access logs."
  type        = number
  default     = 30
}