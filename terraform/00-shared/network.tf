# =============================================================================
# 00-shared: network
# VPC -> public subnet -> route table -> internet gateway
# =============================================================================

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  availability_zone = coalesce(var.availability_zone, data.aws_availability_zones.available.names[0])
}

# Our own private network in AWS
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true # servers can resolve names (github.com, mongodb.net)
  enable_dns_hostnames = true # servers get DNS names

  tags = {
    Name = "${var.project}-vpc"
  }
}

# Lock down the VPC's default firewall: it allows nothing.
# Every server uses its own security group instead (CIS AWS benchmark).
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project}-default-sg-unused"
  }
}

# The door between the VPC and the internet
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project}-igw"
  }
}

# The subnet where all four servers live
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = local.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project}-public-subnet"
    Tier = "public" # server folders find the subnet by this tag
  }
}

# Signpost: "all internet traffic goes through the internet gateway"
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project}-public-rt"
  }
}

resource "aws_route" "internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
