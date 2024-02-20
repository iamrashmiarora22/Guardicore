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

// data "aws_caller_identity" "current" {}

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

# __________________________________________________________________________________________________
# SSH Key File creation

resource "tls_private_key" "pvt_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "pvt_key_file" {
  filename = "ssh-key.pem"
  content  = tls_private_key.pvt_key.private_key_pem
}

resource "aws_key_pair" "key_pair" {
  key_name   = "rashmikey"
  public_key = tls_private_key.pvt_key.public_key_openssh
}


# __________________________________________________________________________________________________
# Orchestration of VPC-specific resources

resource "aws_vpc" "vpc" {
  cidr_block = "192.168.0.0/16"
}

resource "aws_subnet" "server_subnet" {
  cidr_block        = "192.168.0.0/24"
  vpc_id            = aws_vpc.vpc.id
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

resource "aws_route_table_association" "Management_Subnet_Asso" {
  subnet_id      = aws_subnet.server_subnet.id
  route_table_id = aws_route_table.default_rt.id
}




#service group created for LB

resource "aws_security_group" "allow_lb" {
  name        = "allow_lb"
  description = "Allow LB inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.vpc.id


}
resource "aws_vpc_security_group_ingress_rule" "allow_lb_inbound" {
  security_group_id = aws_security_group.allow_lb.id
  cidr_ipv4         = "51.20.188.217/32"
  from_port         = 0
  ip_protocol       = "tcp"
  to_port           = 80
}
resource "aws_vpc_security_group_ingress_rule" "allow_lb_inbound_22" {
  security_group_id = aws_security_group.allow_lb.id
  cidr_ipv4         = "51.20.188.217/32"
  from_port         = 0
  ip_protocol       = "tcp"
  to_port           = 22
}
resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.allow_lb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

#service group created for other servers

resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow ssh inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.vpc.id


}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_inbound" {
  security_group_id = aws_security_group.allow_ssh.id
  cidr_ipv4         = "51.20.188.217/32"
  from_port         = 0
  ip_protocol       = "tcp"
  to_port           = 22
}


resource "aws_vpc_security_group_egress_rule" "allow_all_traffic" {
  security_group_id = aws_security_group.allow_ssh.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

# __________________________________________________________________________________________________
#               Ubuntu Server WEB

resource "aws_instance" "WEB" {
    
  ami             = data.aws_ami.ubuntu_ami.id
  instance_type   = "t2.micro"
  subnet_id       = aws_subnet.server_subnet.id
  private_ip      = "192.168.0.12"
  //user_data       = "sudo yum install httpd -y && sudo systemctl start httpd"
  security_groups = [aws_security_group.allow_ssh.id]
  key_name      = aws_key_pair.key_pair.key_name
connection {
  type = "ssh"
  host = "ubuntu"
  user        = "ubuntu-web"
      private_key = "ssh-key.pem"
}
}


resource "aws_eip" "webmgtpub" {
  domain            = "vpc"
  instance = aws_instance.WEB.id
}

resource "local_file" "output" {
  content  = "foo!"
  filename = "/home/ubuntu/new_project/output.bar"
}
output "web_server_eip" {
  value = aws_eip.webmgtpub.public_ip
}



# Ubuntu Server LB

resource "aws_instance" "LB" {
    
  ami             = data.aws_ami.ubuntu_ami.id
  instance_type   = "t2.micro"
  subnet_id       = aws_subnet.server_subnet.id
  //user_data       = "sudo yum install httpd -y && sudo systemctl start httpd"
  security_groups = [aws_security_group.allow_lb.id]
  key_name = aws_key_pair.key_pair.key_name
  connection {
  type = "ssh"
  host = "ubuntu"
  user        = "ubuntu-lb"
      private_key = "ssh-key.pem"
}
}

resource "aws_eip" "webmgtpub2" {
  domain            = "vpc"
  instance = aws_instance.LB.id
}
  output "LB_server_eip" {
  value = aws_eip.webmgtpub2.public_ip
}
resource "local_file" "output2" {
  content  = "foo!"
  filename = "/home/ubuntu/new_project/output2.bar"
}



# Ubuntu Server DB

resource "aws_instance" "DB" {
    
  ami             = data.aws_ami.ubuntu_ami.id
  instance_type   = "t2.micro"
  subnet_id       = aws_subnet.server_subnet.id
  private_ip      = "192.168.0.13"
  //user_data       = "sudo yum install httpd -y && sudo systemctl start httpd"
  security_groups = [aws_security_group.allow_ssh.id]
  key_name = aws_key_pair.key_pair.key_name
    connection {
  type = "ssh"
  host = "ubuntu"
  user        = "ubuntu-db"
      private_key = "ssh-key.pem"
}
  provisioner "local-exec" {
    command = "echo ${aws_instance.DB.public_ip} >> /home/ubuntu/new_project/dpip.tf"
  }
}

resource "aws_eip" "webmgtpub3" {
  domain            = "vpc"
  instance = aws_instance.DB.id
}
  resource "local_file" "output3" {
  content  = "foo!"
  filename = "/home/ubuntu/new_project/output3.bar"
}

output "DB_server_eip" {
  value = aws_eip.webmgtpub3.public_ip
}








