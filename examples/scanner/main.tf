variable "aws_region" {
  type = "string"
}

provider "aws" {
  region = "${var.aws_region}"
}

variable "vpc_id" {
  type = "string"
}

variable "subnet_id" {
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
  subnet_id = "${var.subnet_id}"
  instance_type = "${var.instance_type}"
  target_account_ids = ["${var.target_account_ids}"]
}

