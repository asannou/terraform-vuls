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

variable "instance_type" {
  type = "string"
}

variable "target_account_ids" {
  type = "list"
}

module "scanner" {
  source = "github.com/asannou/terraform-vuls//scanner"
  vpc_id = "${var.vpc_id}"
  cidr_block = "${var.cidr_block}"
  instance_type = "${var.instance_type}"
  target_account_ids = ["${var.target_account_ids}"]
}

