terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}

data "aws_ami" "ubuntu_ami" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"]
}

/*
data "aws_ami" "ubuntu_ami" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-instance/ubuntu-bionic-18.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"]
}
*/
# __________________________________________________________________________________________________
# SSH Key Pair

resource "tls_private_key" "pvt_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "pvt_key_file" {
  filename        = "ssh-key.pem"
  content         = tls_private_key.pvt_key.private_key_pem
  file_permission = "0600"
}

resource "aws_key_pair" "key_pair" {
  key_name   = "rashmi-key"
  public_key = tls_private_key.pvt_key.public_key_openssh
}
# __________________________________________________________________________________________________
# Orchestration of VPC-specific resources

resource "aws_vpc" "vpc" {
  cidr_block = "192.168.0.0/16"
}

resource "aws_subnet" "server_subnet" {
  cidr_block = "192.168.0.0/24"
  vpc_id     = aws_vpc.vpc.id
}

resource "aws_internet_gateway" "default_igw" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_route_table" "default_rt" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.default_igw.id
  }
}

resource "aws_route_table_association" "server_rta" {
  subnet_id      = aws_subnet.server_subnet.id
  route_table_id = aws_route_table.default_rt.id
}

# Security Groups
resource "aws_security_group" "allow_http" {
  name        = "allow_http"
  description = "Allow HTTP inbound traffic"
  vpc_id      = aws_vpc.vpc.id
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_ingress" {
  security_group_id = aws_security_group.allow_http.id
  cidr_ipv4         = "51.20.188.217/32"
  from_port         = 0
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow SSH inbound traffic"
  vpc_id      = aws_vpc.vpc.id
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ingress" {
  security_group_id = aws_security_group.allow_ssh.id
  cidr_ipv4         = "51.20.188.217/32"
  from_port         = 0
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "allow_all_self" {
  security_group_id = aws_security_group.allow_ssh.id
  cidr_ipv4         = "192.168.0.0/24"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.allow_ssh.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
# ______________________________________________________________________
#               

# Ubuntu Server LB
resource "aws_instance" "LB" {
  ami             = data.aws_ami.ubuntu_ami.id
  instance_type   = "t2.micro"
  subnet_id       = aws_subnet.server_subnet.id
  private_ip      = "192.168.0.11"
  security_groups = [aws_security_group.allow_ssh.id, aws_security_group.allow_http.id]
  key_name        = aws_key_pair.key_pair.key_name
}

resource "aws_eip" "lb_server_eip" {
  domain   = "vpc"
  instance = aws_instance.LB.id
}

# Ubuntu Server WEB
resource "aws_instance" "WEB" {
  ami             = data.aws_ami.ubuntu_ami.id
  instance_type   = "t2.micro"
  subnet_id       = aws_subnet.server_subnet.id
  private_ip      = "192.168.0.12"
  security_groups = [aws_security_group.allow_ssh.id]
  key_name        = aws_key_pair.key_pair.key_name
}

resource "aws_eip" "web_server_eip" {
  domain   = "vpc"
  instance = aws_instance.WEB.id
}

# Ubuntu Server DB
resource "aws_instance" "DB" {
  ami             = data.aws_ami.ubuntu_ami.id
  instance_type   = "t2.micro"
  subnet_id       = aws_subnet.server_subnet.id
  private_ip      = "192.168.0.13"
  security_groups = [aws_security_group.allow_ssh.id]
  key_name        = aws_key_pair.key_pair.key_name
}

resource "aws_eip" "db_server_eip" {
  domain   = "vpc"
  instance = aws_instance.DB.id
}
# ______________________________________________________________________
#  Output

output "WEB_Server_IP" {
  value = aws_eip.web_server_eip.public_ip
}

output "LB_Server_IP" {
  value = aws_eip.lb_server_eip.public_ip
}

output "DB_Server_IP" {
  value = aws_eip.db_server_eip.public_ip
}
