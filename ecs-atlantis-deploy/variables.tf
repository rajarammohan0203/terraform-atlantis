variable "aws_region" {
  description = "AWS Region to deploy to"
  type        = string
  default     = "ap-south-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "github_user" {
  description = "GitHub username"
  type        = string
}

variable "github_repo_allowlist" {
  description = "Atlantis repo allowlist (e.g. github.com/rajarammohan0203/*)"
  type        = string
}

# Note: We do not define the GitHub token or Webhook Secret here in plain text.
# They will be read dynamically from AWS Systems Manager Parameter Store.
