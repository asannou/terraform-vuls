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

variable "availability_zone" {
  type = "string"
}

variable "instance_type" {
  type = "string"
}

variable "target_account_ids" {
  type = "list"
}

module "scanner" {
  source = "github.com/asannou/terraform-vuls//scanner?ref=session-manager"
  vpc_id = "${var.vpc_id}"
  cidr_block = "${var.cidr_block}"
  nat_gateway_id = "${var.nat_gateway_id}"
  availability_zone = "${var.availability_zone}"
  instance_type = "${var.instance_type}"
  target_account_ids = ["${var.target_account_ids}"]
}

output "instance_id" {
  value = "${module.scanner.instance_id}"
}

output "instance_subnet_id" {
  value = "${module.scanner.instance_subnet_id}"
}

