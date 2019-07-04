data "aws_region" "region" {}

data "aws_availability_zones" "az" {
  state = "available"
}

data "aws_caller_identity" "aws" {}

variable "vpc_id" {
  type = "string"
}

variable "cidr_block" {
  type = "string"
}

variable "instance_type" {
  type = "string"
}

variable "target_account_ids" {
  type = "list"
}

resource "aws_subnet" "vpce" {
  count = "${length(data.aws_availability_zones.az.zone_ids)}"
  vpc_id = "${var.vpc_id}"
  availability_zone_id = "${data.aws_availability_zones.az.zone_ids[count.index]}"
  cidr_block = "${cidrsubnet(var.cidr_block, 3, count.index)}"
  tags = {
    Name = "vuls-vpce-${data.aws_availability_zones.az.zone_ids[count.index]}"
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

data "aws_ami" "ami" {
  most_recent = true
  owners = ["amazon"]
  filter {
    name = "architecture"
    values = ["x86_64"]
  }
  filter {
    name = "root-device-type"
    values = ["ebs"]
  }
  filter {
    name = "name"
    values = ["amzn-ami-*-amazon-ecs-optimized"]
  }
  filter {
    name = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name = "block-device-mapping.volume-type"
    values = ["gp2"]
  }
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
    post-yum-security-cron = "${base64encode(file("${path.module}/post-yum-security.cron"))}"
    yum-clean-cron = "${base64encode(file("${path.module}/yum-clean.cron"))}"
    remove-unused-docker-data-cron = "${base64encode(file("${path.module}/remove-unused-docker-data.cron"))}"
    vuls-privatelink-sh = "${base64encode(file("${path.module}/vuls-privatelink.sh"))}"
    vuls-config = "${base64encode(file("${path.module}/config.toml.default"))}"
    vuls-cron = "${base64encode(file("${path.module}/vuls.cron"))}"
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

resource "aws_iam_policy" "ssm" {
  name = "VulsSSMStartSession"
  path = "/"
  policy = "${data.aws_iam_policy_document.ssm.json}"
}

data "aws_iam_policy_document" "ssm" {
  statement {
    actions = ["ssm:StartSession"]
    resources = [
      "arn:aws:ec2:${data.aws_region.region.name}:${data.aws_caller_identity.aws.account_id}:instance/${aws_instance.vuls.id}"
    ]
  }
}

resource "aws_instance" "vuls" {
  ami = "${data.aws_ami.ami.id}"
  instance_type = "${var.instance_type}"
  subnet_id = "${aws_subnet.vpce.*.id[0]}"
  associate_public_ip_address = true
  vpc_security_group_ids = [
    "${aws_security_group.egress.id}",
    "${aws_security_group.scanner.id}"
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

resource "aws_iam_policy" "vuls" {
  count = "${length(var.target_account_ids)}"
  name = "STSAssumeRoleVuls-${var.target_account_ids[count.index]}"
  policy = "${data.aws_iam_policy_document.vuls.*.json[count.index]}"
}

data "aws_iam_policy_document" "vuls" {
  count = "${length(var.target_account_ids)}"
  statement {
    actions = ["sts:AssumeRole"]
    resources = ["arn:aws:iam::${var.target_account_ids[count.index]}:role/VulsRole-${data.aws_caller_identity.aws.account_id}"]
  }
}

resource "aws_iam_role_policy_attachment" "vuls" {
  count = "${length(var.target_account_ids)}"
  role = "${aws_iam_role.vuls.name}"
  policy_arn = "${aws_iam_policy.vuls.*.arn[count.index]}"
}

resource "aws_iam_policy" "vuls-vpce" {
  name = "VulsVpcEndpoint"
  policy = "${data.aws_iam_policy_document.vuls-vpce.json}"
}

data "aws_iam_policy_document" "vuls-vpce" {
  statement {
    actions = [
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeVpcEndpoints"
    ]
    resources = ["*"]
  }
  statement {
    actions = [
      "ec2:CreateVpcEndpoint",
      "ec2:DeleteVpcEndpoints"
    ]
    resources = ["*"]
  }
  statement {
    actions = ["ec2:CreateTags"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy_attachment" "vuls-vpce" {
  role = "${aws_iam_role.vuls.name}"
  policy_arn = "${aws_iam_policy.vuls-vpce.arn}"
}

resource "aws_security_group" "scanner" {
  name = "vuls-scanner"
  vpc_id = "${var.vpc_id}"
  tags {
    Name = "vuls-privatelink"
  }
}

resource "aws_security_group_rule" "scanner-egress" {
  security_group_id = "${aws_security_group.scanner.id}"
  type = "egress"
  protocol = "tcp"
  from_port = 22000
  to_port = 22050
  source_security_group_id = "${aws_security_group.vpce.id}"
}

resource "aws_security_group" "vpce" {
  name = "vuls-vpce"
  vpc_id = "${var.vpc_id}"
  tags {
    Name = "vuls-privatelink"
  }
}

resource "aws_security_group_rule" "vpce-ingress" {
  security_group_id = "${aws_security_group.vpce.id}"
  type = "ingress"
  protocol = "tcp"
  from_port = 22000
  to_port = 22050
  source_security_group_id = "${aws_security_group.scanner.id}"
}

output "scanner_account_id" {
  value = "${data.aws_caller_identity.aws.account_id}"
}

output "scanner_role" {
  value = "${aws_iam_role.vuls.name}"
}

