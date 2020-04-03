variable "aws_region" {
  type = "string"
}

provider "aws" {
  region = "${var.aws_region}"
}

variable "scanner_account_id" {
  type = "string"
}

variable "scanner_role" {
  type = "string"
}

module "target" {
  source = "github.com/asannou/terraform-vuls//target?ref=session-manager"
  scanner_account_id = "${var.scanner_account_id}"
  scanner_role = "${var.scanner_role}"
}

