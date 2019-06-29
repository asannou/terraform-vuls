data "aws_caller_identity" "aws" {}

variable "target_account_ids" {
  type = "list"
}

variable "vuls_role" {
  type = "string"
}

variable "network_interface_id" {
  type = "string"
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
  role = "${var.vuls_role}"
  policy_arn = "${aws_iam_policy.vuls.*.arn[count.index]}"
}

resource "aws_iam_policy" "vuls-vpce" {
  name = "VulsVpcEndpoint"
  policy = "${data.aws_iam_policy_document.vuls-vpce.json}"
}

data "aws_iam_policy_document" "vuls-vpce" {
  statement {
    actions = [
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
  role = "${var.vuls_role}"
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

resource "aws_network_interface_sg_attachment" "scanner" {
  network_interface_id = "${var.network_interface_id}"
  security_group_id = "${aws_security_group.scanner.id}"
}

resource "aws_security_group" "vpce" {
  name = "vuls-privatelink"
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

