data "aws_region" "region" {}

data "aws_caller_identity" "aws" {}

variable "scanner_account_id" {
  type = "string"
}

variable "scanner_role" {
  default = "EC2RoleVuls"
}

variable "vuls_version" {
  default = "v0.9.3"
}

resource "aws_iam_role" "vuls" {
  name = "VulsRole-${var.scanner_account_id}"
  path = "/"
  assume_role_policy = "${data.aws_iam_policy_document.vuls.json}"
}

data "aws_iam_policy_document" "vuls" {
  statement {
    principals {
      type = "AWS"
      identifiers = ["*"]
    }
    condition {
      test = "ArnEquals"
      variable = "aws:PrincipalArn"
      values = ["arn:aws:iam::${var.scanner_account_id}:role/${var.scanner_role}"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_policy" "vuls-ssm" {
  name = "VulsAccess-${var.scanner_account_id}"
  path = "/"
  policy = "${data.aws_iam_policy_document.vuls-ssm.json}"
}

data "aws_iam_policy_document" "vuls-ssm" {
  statement {
    actions = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
  statement {
    actions = ["ssm:DescribeInstanceInformation"]
    resources = ["*"]
  }
  statement {
    actions = ["ssm:SendCommand"]
    resources = [
      "arn:aws:ssm:${data.aws_region.region.name}::document/AWS-UpdateSSMAgent",
      "arn:aws:ssm:${data.aws_region.region.name}:${data.aws_caller_identity.aws.account_id}:document/${aws_ssm_document.vuls.name}",
      "arn:aws:s3:::${aws_s3_bucket.vuls.bucket}"
    ]
  }
  statement {
    actions = ["ssm:SendCommand"]
    resources = ["arn:aws:ec2:${data.aws_region.region.name}:${data.aws_caller_identity.aws.account_id}:instance/*"]
    condition {
      test = "StringEquals"
      variable = "ssm:resourceTag/Vuls"
      values = ["1"]
    }
  }
  statement {
    actions = ["ssm:ListCommands"]
    resources = ["*"]
  }
  statement {
    actions = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${aws_s3_bucket.vuls.bucket}/*"]
  }
  statement {
    actions = ["ssm:StartSession"]
    resources = ["arn:aws:ssm:${data.aws_region.region.name}::document/AWS-StartSSHSession"]
  }
  statement {
    actions = ["ssm:StartSession"]
    resources = ["arn:aws:ec2:${data.aws_region.region.name}:${data.aws_caller_identity.aws.account_id}:instance/*"]
    condition {
      test = "StringEquals"
      variable = "ssm:resourceTag/Vuls"
      values = ["1"]
    }
    condition {
      test = "BoolIfExists"
      variable = "ssm:SessionDocumentAccessCheck"
      values = ["true"]
    }
  }
  statement {
    actions = ["ssm:TerminateSession"]
    resources = ["*"]
    condition {
      test = "StringEquals"
      variable = "ssm:resourceTag/aws:ssmmessages:session-id"
      values = ["$${aws:userid}"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "vuls-ssm" {
  role = "${aws_iam_role.vuls.name}"
  policy_arn = "${aws_iam_policy.vuls-ssm.arn}"
}

locals {
  create_vuls_user = {
    schemaVersion = "2.0"
    description = "Create a new user for Vuls."
    parameters = {
      publickey = {
        type = "String"
        description = "(Required) SSH public key"
        default = ""
        displayType = "textarea"
        allowedPattern = "^[ +\\-./=@0-9A-Za-z]+$"
      }
      sshcommand = {
        type = "String"
        description = "SSH Command S3 URI"
        default = "s3://${aws_s3_bucket_object.vuls.bucket}/${aws_s3_bucket_object.vuls.key}"
        displayType = "textarea"
        allowedPattern = "^[\\-./=@0-9:A-Za-z]+$"
      }
    }
    mainSteps = [
      {
        action = "aws:runShellScript",
        name = "runShellScript",
        inputs = {
          runCommand = "${split("\n", file("${path.module}/create_vuls_user.sh"))}"
        }
      }
    ]
  }
}

resource "aws_ssm_document" "vuls" {
  name = "CreateVulsUser"
  document_type = "Command"
  content = "${jsonencode(local.create_vuls_user)}"
}

resource "aws_s3_bucket" "vuls" {
  bucket = "vuls-ssm-${var.scanner_account_id}-${data.aws_caller_identity.aws.account_id}"
  acl = "private"
  force_destroy = true
}

module "vuls-ssh-command" {
  source = "github.com/asannou/terraform-download-file"
  url = "https://github.com/asannou/vuls-ssh-command/raw/${var.vuls_version}/vuls-ssh-command.sh"
}

resource "aws_s3_bucket_object" "vuls" {
  bucket = "${aws_s3_bucket.vuls.bucket}"
  key = "vuls-ssh-command.sh"
  source = "${module.vuls-ssh-command.filename}"
  etag = "${filemd5(module.vuls-ssh-command.filename)}"
}

