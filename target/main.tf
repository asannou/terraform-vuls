data "aws_region" "region" {}

data "aws_caller_identity" "aws" {}

variable "scanner_account_id" {
  type = "string"
}

variable "scanner_role" {
  type = "string"
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
      identifiers = ["arn:aws:iam::${var.scanner_account_id}:role/${var.scanner_role}"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_policy" "vuls-ssm" {
  name = "VulsSSMAccess"
  path = "/"
  policy = "${data.aws_iam_policy_document.vuls-ssm.json}"
}

data "aws_iam_policy_document" "vuls-ssm" {
  statement {
    actions = ["ec2:DescribeTags"]
    resources = ["*"]
  }
  statement {
    actions = ["ssm:SendCommand"]
    resources = [
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
}

resource "aws_iam_role_policy_attachment" "vuls-ssm" {
  role = "${aws_iam_role.vuls.name}"
  policy_arn = "${aws_iam_policy.vuls-ssm.arn}"
}

resource "aws_iam_policy" "vuls-privatelink" {
  name = "VulsPrivateLink"
  path = "/"
  policy = "${data.aws_iam_policy_document.vuls-privatelink.json}"
}

data "aws_iam_policy_document" "vuls-privatelink" {
  statement {
    actions = [
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInstances",
      "ec2:DescribeVpcEndpointServiceConfigurations"
    ]
    resources = ["*"]
  }
  statement {
    actions = ["lambda:InvokeFunction"]
    resources = ["${aws_lambda_function.lambda.arn}"]
  }
  statement {
    actions = [
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeTargetHealth"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy_attachment" "vuls-privatelink" {
  role = "${aws_iam_role.vuls.name}"
  policy_arn = "${aws_iam_policy.vuls-privatelink.arn}"
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
  url = "https://github.com/asannou/vuls-ssh-command/raw/master/vuls-ssh-command.sh"
}

resource "aws_s3_bucket_object" "vuls" {
  bucket = "${aws_s3_bucket.vuls.bucket}"
  key = "vuls-ssh-command.sh"
  source = "${module.vuls-ssh-command.filename}"
  etag = "${md5(module.vuls-ssh-command.filename)}"
}

resource "aws_lambda_function" "lambda" {
  filename = "${data.archive_file.lambda.output_path}"
  function_name = "vuls-accept-vpc-endpoint-connections"
  role = "${aws_iam_role.lambda.arn}"
  handler = "vuls-accept-vpc-endpoint-connections.handler"
  runtime = "nodejs8.10"
  timeout = "60"
  source_code_hash = "${data.archive_file.lambda.output_base64sha256}"
  environment {
    variables = {
      SERVICE_IDS = "${join(" ", local.vpce_svc_ids)}"
    }
  }
  tags {
    Name = "vuls"
  }
}

data "archive_file" "lambda" {
  type = "zip"
  source_file = "${path.module}/vuls-accept-vpc-endpoint-connections.js"
  output_path = "${path.module}/vuls-accept-vpc-endpoint-connections.zip"
}

resource "aws_iam_role" "lambda" {
  name = "LambdaRoleVulsAcceptVpcEndpointConnections"
  path = "/"
  assume_role_policy = "${data.aws_iam_policy_document.lambda-role.json}"
}

data "aws_iam_policy_document" "lambda-role" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "lambda" {
  role = "${aws_iam_role.lambda.name}"
  policy_arn = "${aws_iam_policy.lambda.arn}"
}

resource "aws_iam_policy" "lambda" {
  name = "AcceptVpcEndpointConnections"
  path = "/"
  policy = "${data.aws_iam_policy_document.lambda.json}"
}

data "aws_iam_policy_document" "lambda" {
  statement {
    effect = "Allow"
    actions = ["ec2:AcceptVpcEndpointConnections"]
    resources = ["*"]
  }
}

locals {
  api_http_method = "POST"
  api_path = "accept-vpc-endpoint-connections"
}

resource "aws_api_gateway_rest_api" "vuls" {
  name = "vuls"
  policy = "${data.aws_iam_policy_document.api.json}"
  endpoint_configuration {
    types = ["PRIVATE"]
  }
}

data "aws_iam_policy_document" "api" {
  statement {
    principals {
      type = "AWS"
      identifiers = ["arn:aws:iam::${var.scanner_account_id}:role/${var.scanner_role}"]
    }
    actions = ["execute-api:Invoke"]
    resources = ["arn:aws:execute-api:*:*:*/*/${local.api_http_method}/${local.api_path}"]
  }
}

resource "aws_api_gateway_resource" "accept-vpc-endpoint-connections" {
  rest_api_id = "${aws_api_gateway_rest_api.vuls.id}"
  parent_id = "${aws_api_gateway_rest_api.vuls.root_resource_id}"
  path_part = "${local.api_path}"
}

resource "aws_api_gateway_method" "post-accept-vpc-endpoint-connections" {
  rest_api_id = "${aws_api_gateway_rest_api.vuls.id}"
  resource_id = "${aws_api_gateway_resource.accept-vpc-endpoint-connections.id}"
  http_method = "${local.api_http_method}"
  authorization = "AWS_IAM"
}

resource "aws_api_gateway_integration" "post-accept-vpc-endpoint-connections" {
  rest_api_id = "${aws_api_gateway_rest_api.vuls.id}"
  resource_id = "${aws_api_gateway_resource.accept-vpc-endpoint-connections.id}"
  http_method = "${local.api_http_method}"
  type = "AWS"
  integration_http_method = "${local.api_http_method}"
  uri = "arn:aws:apigateway:${data.aws_region.region.name}:lambda:path/2015-03-31/functions/${aws_lambda_function.lambda.arn}/invocations"
}

resource "aws_api_gateway_method_response" "200" {
  rest_api_id = "${aws_api_gateway_rest_api.vuls.id}"
  resource_id = "${aws_api_gateway_resource.accept-vpc-endpoint-connections.id}"
  http_method = "${local.api_http_method}"
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "post-accept-vpc-endpoint-connections" {
  rest_api_id = "${aws_api_gateway_rest_api.vuls.id}"
  resource_id = "${aws_api_gateway_resource.accept-vpc-endpoint-connections.id}"
  http_method = "${local.api_http_method}"
  status_code = "${aws_api_gateway_method_response.200.status_code}"
}

resource "aws_lambda_permission" "vuls" {
  action = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.lambda.function_name}"
  principal = "apigateway.amazonaws.com"
  source_arn = "arn:aws:execute-api:${data.aws_region.region.name}:${data.aws_caller_identity.aws.account_id}:${aws_api_gateway_rest_api.vuls.id}/*/${local.api_http_method}/${local.api_path}"
}

resource "aws_api_gateway_deployment" "vuls" {
  depends_on = [
    "aws_api_gateway_resource.accept-vpc-endpoint-connections",
    "aws_api_gateway_method.post-accept-vpc-endpoint-connections",
    "aws_api_gateway_method_response.200",
    "aws_api_gateway_integration.post-accept-vpc-endpoint-connections",
    "aws_api_gateway_integration_response.post-accept-vpc-endpoint-connections",
  ]
  variables {
    depends_on = "${md5(aws_api_gateway_rest_api.vuls.policy)}"
  }
  rest_api_id = "${aws_api_gateway_rest_api.vuls.id}"
  stage_name = "prod"
}

