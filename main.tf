terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
  required_version = ">= 1.8"
}

provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  token      = var.aws_access_token
}

data "aws_vpc" "default" {
  default = true
}

# Lookup Ubuntu AMI automatically
data "aws_ami" "ubuntu_ami" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name = "name"
    values = [
      # "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"
      # "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
      # "ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"
      "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"
    ]
  }
}

# Security Group
resource "aws_security_group" "awx_server_sg" {
  name        = "awx_server_sg"
  description = "Security group for the AWX Server"
  vpc_id      = data.aws_vpc.default.id

  # Inbound rules
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound rules
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "awx_server_sg"
    Terraform = "true"
  }
}

# Generate a new private key
resource "tls_private_key" "awx_server_tls_private_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create an AWS key pair from the generated public key
resource "aws_key_pair" "awx_server_key_pair" {
  key_name   = "my-generated-key"
  public_key = tls_private_key.awx_server_tls_private_key.public_key_openssh
}

data "aws_subnets" "subnets" {
  filter {
    name = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Launch the AWX Server
resource "aws_instance" "awx_server" {
  subnet_id                   = data.aws_subnets.subnets.ids[0]
  instance_type               = var.awx_server_ec2_type
  vpc_security_group_ids      = [aws_security_group.awx_server_sg.id]
  ami                         = data.aws_ami.ubuntu_ami.id
  associate_public_ip_address = true
  monitoring                  = true
  root_block_device {
    volume_size = 40
    volume_type = "gp2"
  }
  key_name  = aws_key_pair.awx_server_key_pair.key_name
  user_data = file("${path.module}/userdata.sh")

  # 1) Copy the entire awx_setup folder to the instance
  provisioner "file" {
    source      = "${path.module}/awx_setup"
    destination = "/home/ubuntu"

    connection {
      type = "ssh"
      host = self.public_ip
      user = "ubuntu"
      private_key = tls_private_key.awx_server_tls_private_key.private_key_pem
    }
  }

  # 2) Remote commands to move files where they belong, fix permissions, enable & start the service
  provisioner "remote-exec" {
    inline = [
      # Making sure the scripts are executable
      "sudo chmod u+x /home/ubuntu/awx_setup/install.sh",
      "sudo chmod u+x /home/ubuntu/awx_setup/start.sh",

      # Run the install script
      "/home/ubuntu/awx_setup/install.sh",

      # Copy service file to systemd directory
      "sudo cp /home/ubuntu/awx_setup/awx-auto.service /etc/systemd/system/awx-auto.service",
      "sudo chmod 644 /etc/systemd/system/awx-auto.service",

      # Enable the service to run on boot
      "sudo systemctl enable awx-auto.service",

      # Reload systemd
      "sudo systemctl daemon-reload",

      # Start the service immediately
      "sudo systemctl start awx-auto.service"
    ]

    connection {
      type        = "ssh"
      host        = self.public_ip
      user        = "ubuntu"
      private_key = tls_private_key.awx_server_tls_private_key.private_key_pem
    }
  }

  tags = {
    Name      = "awx_server"
    Terraform = "true"
  }
}
