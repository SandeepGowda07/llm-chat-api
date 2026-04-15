# ============================================================
# Terraform — EKS Cluster for llm-chat-api
#
# Resources created:
#   Networking  : VPC, 2 Subnets (different AZs), IGW, Route Table
#   IAM         : Cluster Role, Node Role + policy attachments
#   Kubernetes  : EKS Cluster, EKS Node Group
# ============================================================

provider "aws" {
  region = var.aws_region
}

# ─── NETWORKING ───────────────────────────────────────────────────────────────
#
# VPC = your private network in AWS.
# enable_dns_hostnames and enable_dns_support are required by EKS
# so that nodes can resolve each other by hostname.

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "llm-chat-vpc"
  }
}

# EKS requires at least 2 subnets in DIFFERENT Availability Zones.
# Why? So if one data centre (AZ) goes down, your cluster still runs.
# AZ "a" and AZ "b" are physically separate buildings in the same region.

resource "aws_subnet" "subnet_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  # These tags tell EKS which subnets belong to this cluster,
  # and tell AWS to use these subnets when creating Load Balancers.
  tags = {
    Name                                        = "llm-chat-subnet-1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }
}

resource "aws_subnet" "subnet_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "llm-chat-subnet-2"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }
}

# Internet Gateway connects the VPC to the public internet.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "llm-chat-igw"
  }
}

# Route Table says: all traffic (0.0.0.0/0) goes to the internet gateway.
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "llm-chat-rt"
  }
}

# Associate the route table with BOTH subnets so both can reach the internet.
resource "aws_route_table_association" "subnet_1" {
  subnet_id      = aws_subnet.subnet_1.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "subnet_2" {
  subnet_id      = aws_subnet.subnet_2.id
  route_table_id = aws_route_table.main.id
}

# ─── IAM ROLES ────────────────────────────────────────────────────────────────
#
# AWS uses IAM (Identity and Access Management) to control what can do what.
# EKS needs TWO separate roles:
#
# 1. CLUSTER ROLE — used by the EKS control plane itself.
#    It needs permission to manage ENIs (network interfaces), security groups,
#    and load balancers on your behalf.
#
# 2. NODE ROLE — used by the EC2 worker nodes.
#    They need permission to pull images, register with the cluster,
#    and manage pod networking.
#
# "assume_role_policy" = who is allowed to USE this role.
# In role 1: the EKS service (eks.amazonaws.com) can use it.
# In role 2: EC2 instances (ec2.amazonaws.com) can use it.

resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

# Attach AWS's managed policy that gives EKS the permissions it needs.
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Node role — for the EC2 worker nodes.
resource "aws_iam_role" "eks_node_role" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Three policies the worker nodes need:
# 1. WorkerNodePolicy      — lets nodes register with the EKS cluster
# 2. CNI_Policy            — lets nodes manage pod networking (IP addresses)
# 3. ContainerRegistryRead — lets nodes pull images from ECR (or Docker Hub)
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ─── EKS CLUSTER ──────────────────────────────────────────────────────────────
#
# This creates the Kubernetes CONTROL PLANE — the "brain" of the cluster.
# AWS manages the master nodes (API server, scheduler, etcd) for you.
# You never SSH into them. You just talk to the API endpoint.
#
# depends_on ensures the IAM role has its policies attached BEFORE
# the cluster is created — otherwise EKS starts without permissions.

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

# ─── EKS NODE GROUP ───────────────────────────────────────────────────────────
#
# Node Group = the EC2 instances that actually RUN your pods.
# AWS manages them — if a node crashes, AWS replaces it automatically.
#
# scaling_config:
#   desired_size = how many nodes to run normally (1 = cheapest)
#   min_size     = never go below this (1 = always have at least 1 node)
#   max_size     = never exceed this (2 = can scale up if needed)
#
# depends_on ensures ALL three node policies are attached before
# nodes try to join the cluster.

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-nodes"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]
  instance_types  = [var.instance_type]

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy,
  ]
}
