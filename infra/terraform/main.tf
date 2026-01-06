locals {
  name_prefix  = "${var.project_name}-${var.env}-jenkins"
  jenkins_fqdn = "${var.jenkins_subdomain}.${var.root_domain}"

  common_tags = {
    Project   = var.project_name
    Env       = var.env
    Component = "jenkins"
    ManagedBy = "terraform"
  }

  ssm_param_arn = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${var.ssm_aws_creds_param_name}"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "imported" {
  count      = var.public_key_path != "" ? 1 : 0
  key_name   = var.key_name
  public_key = file(var.public_key_path)
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "jenkins" {
  statement {
    sid    = "SSMParameter"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters"
    ]
    resources = [local.ssm_param_arn]
  }

  statement {
    sid    = "DescribeTags"
    effect = "Allow"
    actions = [
      "ec2:DescribeTags"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "jenkins" {
  name               = "jenkins-user"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "jenkins" {
  name   = "${local.name_prefix}-policy"
  role   = aws_iam_role.jenkins.id
  policy = data.aws_iam_policy_document.jenkins.json
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "jenkins-user"
  role = aws_iam_role.jenkins.name
}

resource "aws_security_group" "jenkins" {
  name        = "${local.name_prefix}-sg"
  description = "Jenkins inbound and SSH"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-sg" })
}

resource "aws_instance" "jenkins" {
  ami                                  = data.aws_ami.ubuntu.id
  instance_type                        = var.instance_type
  subnet_id                            = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids               = [aws_security_group.jenkins.id]
  key_name                             = var.key_name
  iam_instance_profile                 = aws_iam_instance_profile.jenkins.name
  instance_initiated_shutdown_behavior = "stop"
  associate_public_ip_address          = true

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/userdata.sh.tftpl", {
    jenkins_fqdn         = local.jenkins_fqdn
    enable_ssm_aws_creds = var.enable_ssm_aws_creds
    ssm_param_name       = var.ssm_aws_creds_param_name
    aws_region           = var.aws_region
    jenkins_admin_email  = var.jenkins_admin_email
  })

  user_data_replace_on_change = true

  tags = merge(local.common_tags, {
    Name              = local.name_prefix
    AutoShutdownHours = var.auto_shutdown_hours
  })
}

resource "aws_eip" "jenkins" {
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-eip" })
}

resource "aws_eip_association" "jenkins" {
  instance_id   = aws_instance.jenkins.id
  allocation_id = aws_eip.jenkins.id
}

resource "aws_route53_record" "jenkins" {
  zone_id = var.hosted_zone_id
  name    = local.jenkins_fqdn
  type    = "A"
  ttl     = 60
  records = [aws_eip.jenkins.public_ip]
}
