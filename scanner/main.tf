data "aws_region" "region" {}

data "aws_caller_identity" "aws" {}

variable "vpc_id" {
  type = "string"
}

variable "cidr_block" {
  type = "string"
}

variable "nat_gateway_id" {
  type = "string"
}

variable "instance_type" {
  type = "string"
  default = "t4g.medium"
}

variable "slack_channel" {
  default = ""
}

variable "slack_auth_user" {
  default = ""
}

variable "slack_notify_users" {
  default = []
}

resource "aws_subnet" "vuls" {
  vpc_id = "${var.vpc_id}"
  cidr_block = "${var.cidr_block}"
  map_public_ip_on_launch = false
  tags = {
    Name = "vuls"
  }
}

resource "aws_route_table_association" "vuls" {
  subnet_id = "${aws_subnet.vuls.id}"
  route_table_id = "${aws_route_table.vuls.id}"
}

resource "aws_route_table" "vuls" {
  vpc_id = "${var.vpc_id}"
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = "${var.nat_gateway_id}"
  }
  tags = {
    Name = "vuls"
  }
}

resource "aws_security_group" "egress" {
  name = "vuls-egress"
  vpc_id = "${var.vpc_id}"
  tags {
    Name = "vuls"
  }
}

resource "aws_security_group_rule" "egress" {
  security_group_id = "${aws_security_group.egress.id}"
  type = "egress"
  protocol = "all"
  from_port = 0
  to_port = 0
  cidr_blocks = ["0.0.0.0/0"]
}

data "aws_ssm_parameter" "image_id" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/arm64/recommended/image_id"
}

data "template_cloudinit_config" "user_data" {
  gzip = true
  base64_encode = true
  part {
    content_type = "text/cloud-config"
    content = "${data.template_file.user_data.rendered}"
  }
}

data "template_file" "user_data" {
  template = "${file("${path.module}/user_data.yml.tpl")}"
  vars {
    docker-logrotate = "${base64encode(file("${path.module}/docker.logrotate"))}"
    yum-cron-security-conf = "${base64encode(file("${path.module}/yum-cron-security.conf"))}"
    yum-security-cron = "${base64encode(file("${path.module}/yum-security.cron"))}"
    yum-clean-cron = "${base64encode(file("${path.module}/yum-clean.cron"))}"
    vuls-cron = "${base64encode(file("${path.module}/vuls.cron"))}"
    remove-unused-docker-data-cron = "${base64encode(file("${path.module}/remove-unused-docker-data.cron"))}"
    post-yum-security-cron = "${base64encode(file("${path.module}/post-yum-security.cron"))}"
    gost-patch = "${base64encode(file("${path.module}/gost.patch"))}"
    vuls-patch = "${base64encode(file("${path.module}/vuls.patch"))}"
    sockguard-patch = "${base64encode(file("${path.module}/sockguard.patch"))}"
    vuls-build-sh = "${base64encode(file("${path.module}/vuls-build.sh"))}"
    vuls-fetch-sh = "${base64encode(file("${path.module}/vuls-fetch.sh"))}"
    vuls-sh = "${base64encode(file("${path.module}/vuls.sh"))}"
    vuls-config-slack = "${base64encode(data.template_file.config_slack.rendered)}"
  }
}

data "template_file" "config_slack" {
  template = "${file("${path.module}/config.slack.toml.tpl")}"
  vars {
    channel = "${var.slack_channel}"
    authUser = "${var.slack_auth_user}"
    notifyUsers = "${jsonencode(var.slack_notify_users)}"
  }
}

resource "aws_iam_role" "vuls" {
  name = "EC2RoleVuls"
  path = "/"
  assume_role_policy = "${data.aws_iam_policy_document.role.json}"
}

data "aws_iam_policy_document" "role" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_instance_profile" "vuls" {
  name = "${aws_iam_role.vuls.name}"
  role = "${aws_iam_role.vuls.name}"
}

resource "aws_iam_role_policy_attachment" "ec2-ssm" {
  role = "${aws_iam_role.vuls.name}"
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_policy" "ec2-sts" {
  name = "VulsAssumeRole"
  policy = "${data.aws_iam_policy_document.ec2-sts.json}"
}

data "aws_iam_policy_document" "ec2-sts" {
  statement {
    actions = ["sts:AssumeRole"]
    resources = ["arn:aws:iam::*:role/VulsRole-${data.aws_caller_identity.aws.account_id}"]
  }
}

resource "aws_iam_role_policy_attachment" "ec2-sts" {
  role = "${aws_iam_role.vuls.name}"
  policy_arn = "${aws_iam_policy.ec2-sts.arn}"
}

resource "aws_iam_policy" "ec2-secretsmanager" {
  name = "VulsGetSecretValue"
  path = "/"
  policy = "${data.aws_iam_policy_document.ec2-secretsmanager.json}"
}

data "aws_iam_policy_document" "ec2-secretsmanager" {
  statement {
    actions = ["secretsmanager:GetSecretValue"],
    resources = ["${aws_secretsmanager_secret.vuls.arn}"]
  }
}

resource "aws_iam_role_policy_attachment" "ec2-secretsmanager" {
  role = "${aws_iam_role.vuls.name}"
  policy_arn = "${aws_iam_policy.ec2-secretsmanager.arn}"
}

resource "aws_instance" "vuls" {
  ami = "${data.aws_ssm_parameter.image_id.value}"
  instance_type = "${var.instance_type}"
  subnet_id = "${aws_subnet.vuls.id}"
  associate_public_ip_address = false
  vpc_security_group_ids = [
    "${aws_security_group.egress.id}",
  ]
  user_data_base64 = "${data.template_cloudinit_config.user_data.rendered}"
  iam_instance_profile = "${aws_iam_instance_profile.vuls.name}"
  lifecycle {
    ignore_changes = [
      "ami"
    ]
  }
  tags {
    Name = "vuls"
  }
}

resource "aws_secretsmanager_secret" "vuls" {
  name = "vuls-slack-webhook-url"
}

resource "aws_secretsmanager_secret_version" "vuls" {
  secret_id = "${aws_secretsmanager_secret.vuls.id}"
  secret_string = "https://hooks.slack.com/services/abc123/defghijklmnopqrstuvwxyz"
  lifecycle {
    ignore_changes = [
      "secret_string"
    ]
  }
}

output "instance_id" {
  value = "${aws_instance.vuls.id}"
}

output "instance_subnet_id" {
  value = "${aws_instance.vuls.subnet_id}"
}

