variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "aws_profile" {
  description = "Optional AWS CLI profile to use"
  type        = string
  default     = ""
}

variable "project_name" {
  description = "Project name used for tagging and resource names"
  type        = string
}

variable "env" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for Jenkins"
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB"
  type        = number
  default     = 30
}

variable "key_name" {
  description = "Existing EC2 key pair name to attach"
  type        = string
}

variable "public_key_path" {
  description = "Path to a public key file to import as a key pair (optional)"
  type        = string
  default     = ""
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH (port 22)"
  type        = string
}

variable "root_domain" {
  description = "Root domain name (Route53 hosted zone must exist)"
  type        = string
}

variable "jenkins_subdomain" {
  description = "Subdomain to use for Jenkins"
  type        = string
  default     = "jenkins"
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID for the root domain"
  type        = string
}

variable "auto_shutdown_hours" {
  description = "Number of hours after boot to auto-shutdown the instance"
  type        = number
  default     = 6
}

variable "enable_ssm_aws_creds" {
  description = "If true, fetch AWS creds from SSM SecureString and expose as env vars for Jenkins"
  type        = bool
  default     = false
}

variable "ssm_aws_creds_param_name" {
  description = "SSM SecureString parameter name containing AWS credentials JSON"
  type        = string
  default     = "/jenkins/aws-creds"
}

variable "jenkins_admin_email" {
  description = "Optional email used for Let's Encrypt certificates via certbot"
  type        = string
  default     = ""
}
