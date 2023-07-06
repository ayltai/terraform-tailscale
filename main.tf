terraform {
  required_version = ">= 1.5.0"

  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "tailscale"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }

    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.13"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = var.aws_region
}

provider "tailscale" {
  api_key = var.tailscale_api_key
  tailnet = var.tailscale_tailnet
}

resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr_block
}

resource "aws_subnet" "this" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.subnet_cidr_block
  availability_zone = "${var.aws_region}a"
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
}

resource "aws_eip" "this" {
  instance = aws_instance.this.id
  vpc      = true

  depends_on = [
    aws_internet_gateway.this,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route_table" "this" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
}

resource "aws_route_table_association" "this" {
  route_table_id = aws_route_table.this.id
  subnet_id      = aws_subnet.this.id
}

resource "aws_security_group" "this" {
  name   = "${var.server_hostname}-${var.aws_region}"
  vpc_id = aws_vpc.this.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"

    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }
}

resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "this" {
  key_name   = "${var.server_hostname}-${var.aws_region}"
  public_key = tls_private_key.this.public_key_openssh
}

resource "aws_ssm_parameter" "this" {
  name  = "/tailscale/${var.server_hostname}-${var.aws_region}"
  type  = "SecureString"
  value = tls_private_key.this.private_key_pem
}

resource "aws_instance" "this" {
  ami           = data.aws_ami.this.id
  instance_type = var.server_instance_type
  subnet_id     = aws_subnet.this.id
  key_name      = aws_key_pair.this.key_name

  vpc_security_group_ids = [
    aws_security_group.this.id,
  ]

  root_block_device {
    volume_size = var.server_storage_size
  }
}

resource "tailscale_tailnet_key" "this" {
  reusable      = true
  preauthorized = true
  expiry        = var.tailscale_tailnet_key_expiry
}

resource "null_resource" "this" {
  triggers = {
    server_id = aws_instance.this.id
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update",
      "sudo apt -qq install software-properties-common apt-transport-https ca-certificates lsb-release curl -y",
      "curl -fsSL ${var.tailscale_package_url}.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null",
      "curl -fsSL ${var.tailscale_package_url}.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list",
      "sudo apt update",
      "sudo apt -qq install tailscale -y",
      "sudo tailscale up --advertise-exit-node --exit-node=${aws_eip.this.public_ip} --hostname=${var.server_hostname}-${var.aws_region} --authkey=${tailscale_tailnet_key.this.key}",
      "systemctl enable --now tailscaled",
    ]

    connection {
      agent       = false
      timeout     = var.timeout
      host        = aws_eip.this.public_ip
      private_key = tls_private_key.this.private_key_pem
      user        = var.server_username
    }
  }
}
