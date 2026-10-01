locals {
  name = "technova-reservas"
}
module "vpc" {
  source = "./modules/vpc"
  name   = local.name
}
module "security_group" {
  source          = "./modules/security-group"
  name            = local.name
  vpc_id          = module.vpc.vpc_id
  access_cidr     = var.access_cidr
  api_extra_cidrs = var.api_extra_cidrs
}
module "rds" {
  source             = "./modules/rds"
  name               = local.name
  private_subnet_ids = module.vpc.private_subnet_ids
  security_group_id  = module.security_group.rds_sg_id
  db_password        = var.db_password
}
module "ec2" {
  source            = "./modules/ec2"
  name              = local.name
  public_subnet_id  = module.vpc.public_subnet_ids[0]
  security_group_id = module.security_group.ec2_sg_id
  ssh_public_key    = var.ssh_public_key
  # Aguarda também rotas e regras necessárias ao cloud-init.
  depends_on = [module.vpc, module.security_group]
}
