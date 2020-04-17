variable "aws_region" {
  type = "string"
}

provider "aws" {
  region = "${var.aws_region}"
}

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

variable "slack_channel" {
  type = "string"
}

module "scanner" {
  source = "github.com/asannou/terraform-vuls//scanner?ref=session-manager"
  vpc_id = "${var.vpc_id}"
  cidr_block = "${var.cidr_block}"
  nat_gateway_id = "${var.nat_gateway_id}"
  instance_type = "${var.instance_type}"
  instance_public_key = "${var.instance_public_key}"
  slack_channel = "${var.slack_channel}"
}

output "instance_id" {
  value = "${module.scanner.instance_id}"
}

output "instance_subnet_id" {
  value = "${module.scanner.instance_subnet_id}"
}

