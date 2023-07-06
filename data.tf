data "aws_ami" "this" {
  filter {
    name = "name"

    values = [
      var.ami_filter,
    ]
  }

  filter {
    name = "virtualization-type"

    values = [
      "hvm",
    ]
  }

  owners = [
    var.ami_owner,
  ]

  most_recent = true
}

data "aws_iam_policy_document" "lambda" {
  version = "2012-10-17"

  statement {
    effect = "Allow"

    principals {
      type = "Service"

      identifiers = [
        "lambda.amazonaws.com",
      ]
    }

    actions = [
      "sts:AssumeRole",
    ]
  }
}

data "aws_iam_policy_document" "instance" {
  version = "2012-10-17"

  statement {
    effect = "Allow"

    resources = [
      "*",
    ]

    actions = [
      "ec2:Start*",
      "ec2:Stop*",
    ]
  }
}

data "aws_iam_policy_document" "cloudwatch" {
  version = "2012-10-17"

  statement {
    effect = "Allow"

    resources = [
      "arn:aws:logs:*:*:*",
    ]

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
  }
}

data "archive_file" "start_instance" {
  type                    = "zip"
  output_path             = "${path.module}/start_instance.zip"
  source_content_filename = "${path.module}/start_instance.js"
  source_content          = <<EOF
const AWS = require('aws-sdk');
const ec2 = new AWS.EC2({
  region: '${var.aws_region}',
});

exports.handler = async (event, context, callback) => await ec2.startInstances({
  InstanceIds: [
    '${aws_instance.this.id}',
  ],
}).promise();
  EOF
}

data "archive_file" "stop_instance" {
  type                    = "zip"
  output_path             = "${path.module}/stop_instance.zip"
  source_content_filename = "${path.module}/stop_instance.js"
  source_content          = <<EOF
const AWS = require('aws-sdk');
const ec2 = new AWS.EC2({
  region: '${var.aws_region}',
});

exports.handler = async (event, context, callback) => await ec2.stopInstances({
  InstanceIds: [
    '${aws_instance.this.id}',
  ],
}).promise();
  EOF
}
