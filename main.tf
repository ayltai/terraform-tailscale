terraform {
  required_version = ">= 1.5.0"

  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "tailscale"

    workspaces {
      name = "main"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.6"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
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
  region = var.aws_region
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
  domain   = "vpc"

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

resource "aws_iam_role" "lambda" {
  name               = "tailscale"
  assume_role_policy = data.aws_iam_policy_document.lambda.json
}

resource "aws_iam_policy" "lambda" {
  name   = "tailscale-lambda"
  path   = "/"
  policy = data.aws_iam_policy_document.instance.json
}

resource "aws_iam_policy" "cloudwatch" {
  name   = "tailscale-cloudwatch"
  path   = "/"
  policy = data.aws_iam_policy_document.cloudwatch.json
}

resource "aws_iam_role_policy_attachment" "lambda" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda.arn
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.cloudwatch.arn
}

resource "aws_cloudwatch_log_group" "start_instance" {
  name              = "/aws/lambda/${var.server_hostname}-${var.aws_region}-start-instance"
  retention_in_days = var.log_retention
}

resource "aws_cloudwatch_log_group" "stop_instance" {
  name              = "/aws/lambda/${var.server_hostname}-${var.aws_region}-stop-instance"
  retention_in_days = var.log_retention
}

resource "aws_cloudwatch_event_rule" "start_instance" {
  name                = "${var.server_hostname}-${var.aws_region}-start-instance"
  schedule_expression = var.server_start_expression
}

resource "aws_cloudwatch_event_rule" "stop_instance" {
  name                = "${var.server_hostname}-${var.aws_region}-stop-instance"
  schedule_expression = var.server_stop_expression
}

resource "aws_s3_bucket" "this" {
  bucket        = "${var.server_hostname}-${var.aws_region}"
  force_destroy = true
}

resource "aws_s3_object" "start_instance" {
  bucket = aws_s3_bucket.this.id
  key    = "start_instance.zip"
  source = data.archive_file.start_instance.output_path
}

resource "aws_s3_object" "stop_instance" {
  bucket = aws_s3_bucket.this.id
  key    = "stop_instance.zip"
  source = data.archive_file.stop_instance.output_path
}

resource "aws_lambda_function" "start_instance" {
  function_name = "${var.server_hostname}-${var.aws_region}-start-instance"
  role          = aws_iam_role.lambda.arn
  s3_bucket     = aws_s3_bucket.this.id
  s3_key        = aws_s3_object.start_instance.id
  handler       = "start_instance.handler"
  runtime       = "nodejs16.x"
  memory_size   = 128
  timeout       = 60

  architectures = [
    "arm64",
  ]

  depends_on = [
    aws_cloudwatch_log_group.start_instance,
  ]
}

resource "aws_lambda_function" "stop_instance" {
  function_name = "${var.server_hostname}-${var.aws_region}-stop-instance"
  role          = aws_iam_role.lambda.arn
  s3_bucket     = aws_s3_bucket.this.id
  s3_key        = aws_s3_object.stop_instance.id
  handler       = "stop_instance.handler"
  runtime       = "nodejs16.x"
  memory_size   = 128
  timeout       = 60

  architectures = [
    "arm64",
  ]

  depends_on = [
    aws_cloudwatch_log_group.stop_instance,
  ]
}

resource "aws_cloudwatch_event_target" "start_instance" {
  rule      = aws_cloudwatch_event_rule.start_instance.name
  target_id = aws_cloudwatch_event_rule.start_instance.name
  arn       = aws_lambda_function.start_instance.arn
}

resource "aws_cloudwatch_event_target" "stop_instance" {
  rule      = aws_cloudwatch_event_rule.stop_instance.name
  target_id = aws_cloudwatch_event_rule.stop_instance.name
  arn       = aws_lambda_function.stop_instance.arn
}

resource "aws_lambda_permission" "start_instance" {
  statement_id  = "AllowExecutionFromCloudWatch"
  principal     = "events.amazonaws.com"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start_instance.function_name
  source_arn    = aws_cloudwatch_event_rule.start_instance.arn
}

resource "aws_lambda_permission" "stop_instance" {
  statement_id  = "AllowExecutionFromCloudWatch"
  principal     = "events.amazonaws.com"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stop_instance.function_name
  source_arn    = aws_cloudwatch_event_rule.stop_instance.arn
}

resource "tailscale_tailnet_key" "this" {
  reusable      = true
  preauthorized = true
  expiry        = var.tailscale_tailnet_key_expiry
}

resource "null_resource" "this" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update",
      "sudo apt -qq install software-properties-common apt-transport-https ca-certificates lsb-release curl -y",
      "curl -fsSL ${var.tailscale_package_url}.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null",
      "curl -fsSL ${var.tailscale_package_url}.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list",
      "sudo apt update",
      "sudo apt -qq install tailscale -y",
      "sudo sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf",
      "sudo sed -i 's/#net.ipv6.conf.all.forwarding=1/net.ipv6.conf.all.forwarding=1/' /etc/sysctl.conf",
      "sudo sysctl -p",
      "sudo tailscale up --advertise-exit-node --hostname=${var.server_hostname}-${var.aws_region} --authkey=${tailscale_tailnet_key.this.key}",
      "sudo systemctl enable --now tailscaled",
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
