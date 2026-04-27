terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.3"
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile
}

# ---------------------------------------------------------------------------
# Lightsail instance
# ---------------------------------------------------------------------------
resource "aws_lightsail_instance" "coder" {
  name              = var.instance_name
  availability_zone = "${var.region}a"
  blueprint_id      = "ubuntu_24_04"
  bundle_id         = var.bundle_id
  user_data         = file("${path.module}/../cloud-init.sh")

  tags = {
    Project = "coder-claude"
  }
}

# ---------------------------------------------------------------------------
# Static IP
# ---------------------------------------------------------------------------
resource "aws_lightsail_static_ip" "coder" {
  name = "${var.instance_name}-ip"
}

resource "aws_lightsail_static_ip_attachment" "coder" {
  static_ip_name = aws_lightsail_static_ip.coder.name
  instance_name  = aws_lightsail_instance.coder.name
}

# ---------------------------------------------------------------------------
# Firewall rules
# ---------------------------------------------------------------------------
resource "aws_lightsail_instance_public_ports" "coder" {
  instance_name = aws_lightsail_instance.coder.name

  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
  }

  port_info {
    protocol  = "tcp"
    from_port = 80
    to_port   = 80
  }

  port_info {
    protocol  = "tcp"
    from_port = 443
    to_port   = 443
  }

  depends_on = [aws_lightsail_instance.coder]
}
