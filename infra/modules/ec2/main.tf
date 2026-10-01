data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}
# Par de chaves EC2 não é um recurso IAM.
resource "aws_key_pair" "this" {
  key_name_prefix = "${var.name}-"
  public_key      = var.ssh_public_key
  tags            = { Name = "${var.name}-ssh" }
}
resource "aws_instance" "this" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t2.micro"
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.this.key_name
  iam_instance_profile        = "LabInstanceProfile"
  user_data                   = file("${path.module}/user_data.sh")
  user_data_replace_on_change = true
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  root_block_device {
    volume_size           = 12
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
    tags                  = { Name = "${var.name}-root", Project = var.name, Environment = "learner-lab", ManagedBy = "terraform" }
  }
  tags = { Name = "${var.name}-ec2" }
}
