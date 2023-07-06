variable "aws_access_key" {
  description = "AWS access key"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS secret key"
  type        = string
  sensitive   = true
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-east-1"
}

variable "vpc_cidr_block" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/24"
}

variable "subnet_cidr_block" {
  description = "Subnet CIDR block"
  type        = string
  default     = "10.0.0.0/28"
}

variable "ami_filter" {
  description = "AMI filter"
  type        = string
  default     = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
}

variable "ami_owner" {
  description = "AMI owner is Canonical"
  default     = "099720109477"
}

variable "server_instance_type" {
  description = "Server instance type"
  type        = string
  default     = "t4g.nano"
}

variable "server_storage_size" {
  description = "Server storage size"
  type        = number
  default     = 8
}

variable "server_username" {
  description = "AMI user"
  default     = "ubuntu"
}

variable "server_hostname" {
  description = "Server hostname"
  type        = string
  default     = "vpn"
}

variable "tailscale_api_key" {
  description = "Tailscale API access token"
  type        = string
  sensitive   = true
}

variable "tailscale_tailnet" {
  description = "Tailscale tailnet name"
  type        = string
  sensitive   = true
}

variable "tailscale_tailnet_key_expiry" {
  description = "Tailscale tailnet key expiry"
  type        = number
  default     = 2419200
}

variable "tailscale_package_url" {
  description = "Tailscale package download URL"
  type        = string
  default     = "https://pkgs.tailscale.com/stable/ubuntu/jammy"
}

variable "timeout" {
  description = "Provision timeout"
  type        = string
  default     = "30m"
}
