resource "aws_security_group" "ec2" {
  name_prefix = "${var.name}-ec2-"
  description = "SSH e API apenas a partir do IPv4 do aluno"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-ec2-sg" }
}
resource "aws_security_group" "rds" {
  name_prefix = "${var.name}-rds-"
  description = "PostgreSQL apenas a partir do SG da EC2"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-rds-sg" }
}
resource "aws_vpc_security_group_ingress_rule" "ec2" {
  for_each          = { ssh = 22, api = 3000 }
  security_group_id = aws_security_group.ec2.id
  cidr_ipv4         = var.access_cidr
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
  tags              = { Name = "${var.name}-${each.key}-in" }
}
resource "aws_vpc_security_group_ingress_rule" "postgres" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.ec2.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  tags                         = { Name = "${var.name}-postgres-in" }
}
resource "aws_vpc_security_group_egress_rule" "postgres" {
  security_group_id            = aws_security_group.ec2.id
  referenced_security_group_id = aws_security_group.rds.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  tags                         = { Name = "${var.name}-postgres-out" }
}
resource "aws_vpc_security_group_egress_rule" "downloads" {
  for_each          = { http = 80, https = 443 }
  security_group_id = aws_security_group.ec2.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
  tags              = { Name = "${var.name}-${each.key}-out" }
}
# DNS do resolvedor da VPC não é filtrado por SG. RDS não inicia tráfego de saída.

resource "aws_vpc_security_group_ingress_rule" "api_extra" {
  for_each          = setsubtract(var.api_extra_cidrs, toset([var.access_cidr]))
  security_group_id = aws_security_group.ec2.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 3000
  to_port           = 3000
  tags              = { Name = "${var.name}-api-extra-${replace(each.value, "/", "-")}" }
}
