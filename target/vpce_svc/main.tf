variable "scanner_account_id" {
  type = "string"
}

variable "subnet_ids" {
  type = "list"
}

variable "base_port" {
  default = "22000"
}

data "aws_subnet" "subnet" {
  id = "${var.subnet_ids[0]}"
}

data "aws_instances" "target" {
  filter {
    name = "subnet-id"
    values = ["${var.subnet_ids}"]
  }
  instance_tags = {
    Vuls = "1"
  }
  instance_state_names = ["running"]
}

data "aws_instance" "target" {
  count = "${length(data.aws_instances.target.ids)}"
  instance_id = "${data.aws_instances.target.ids[count.index]}"
}

resource "aws_vpc_endpoint_service" "vpce-service" {
  acceptance_required = true
  network_load_balancer_arns = ["${aws_lb.nlb.arn}"]
  tags = {
    Name = "vuls"
  }
}

resource "aws_vpc_endpoint_service_allowed_principal" "principal" {
  vpc_endpoint_service_id = "${aws_vpc_endpoint_service.vpce-service.id}"
  principal_arn = "arn:aws:iam::${var.scanner_account_id}:root"
}

resource "aws_lb" "nlb" {
  name_prefix = "vuls-"
  internal = true
  load_balancer_type = "network"
  subnets = ["${var.subnet_ids}"]
  tags = {
    Name = "vuls"
  }
}

resource "aws_lb_listener" "nlb" {
  count = "${length(data.aws_instances.target.ids)}"
  load_balancer_arn = "${aws_lb.nlb.arn}"
  port = "${var.base_port + 1 + count.index}"
  protocol = "TCP"
  default_action {
    type = "forward"
    target_group_arn = "${aws_lb_target_group.nlb.*.arn[count.index]}"
  }
}

resource "aws_lb_target_group" "nlb" {
  count = "${length(data.aws_instances.target.ids)}"
  name_prefix = "vuls-"
  port = 22
  protocol = "TCP"
  vpc_id = "${data.aws_subnet.subnet.vpc_id}"
}

resource "aws_lb_target_group_attachment" "nlb" {
  count = "${length(data.aws_instances.target.ids)}"
  target_group_arn = "${aws_lb_target_group.nlb.*.arn[count.index]}"
  target_id = "${data.aws_instances.target.ids[count.index]}"
  port = 22
}

resource "aws_security_group" "nlb" {
  name_prefix = "vuls-"
  vpc_id = "${data.aws_subnet.subnet.vpc_id}"
  tags = {
    Name = "vuls"
  }
}

data "aws_network_interface" "nlb" {
  filter {
    name = "description"
    values = ["ELB ${aws_lb.nlb.arn_suffix}"]
  }
  filter {
    name = "interface-type"
    values = ["network_load_balancer"]
  }
  filter {
    name = "subnet-id"
    values = ["${var.subnet_ids}"]
  }
}

resource "aws_security_group_rule" "nlb" {
  security_group_id = "${aws_security_group.nlb.id}"
  type = "ingress"
  protocol = "tcp"
  from_port = 22
  to_port = 22
  cidr_blocks = ["${data.aws_network_interface.nlb.private_ip}/32"]
}

resource "aws_network_interface_sg_attachment" "sg_attachment" {
  count = "${length(data.aws_instances.target.ids)}"
  network_interface_id = "${data.aws_instance.target.*.network_interface_id[count.index]}"
  security_group_id = "${aws_security_group.nlb.id}"
}

output "vpce-service.id" {
  value = "${aws_vpc_endpoint_service.vpce-service.id}"
}

output "vpce-service.service_name" {
  value = "${aws_vpc_endpoint_service.vpce-service.service_name}"
}

output "nlb.arn" {
  value = "${aws_lb.nlb.arn}"
}

