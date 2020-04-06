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
}

variable "instance_public_key" {
  type = "string"
}

variable "target_account_ids" {
  type = "list"
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
    vuls-sh = "${base64encode(file("${path.module}/vuls.sh"))}"
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

resource "aws_key_pair" "vuls" {
  key_name = "vuls"
  public_key = "${var.instance_public_key}"
}

resource "aws_instance" "vuls" {
  ami = "${data.aws_ami.ami.id}"
  instance_type = "${var.instance_type}"
  key_name = "${aws_key_pair.vuls.key_name}"
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

resource "aws_iam_policy" "vuls" {
  count = "${length(var.target_account_ids)}"
  name = "VulsAssumeRole-${var.target_account_ids[count.index]}"
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

output "instance_id" {
  value = "${aws_instance.vuls.id}"
}

output "instance_subnet_id" {
  value = "${aws_instance.vuls.subnet_id}"
}

