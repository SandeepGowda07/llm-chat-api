# Tell Terraform to use AWS
provider "aws" {
  region = var.aws_region
}

# Create a VPC - your private network
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "llm-chat-vpc"
  }
}

# Create a subnet inside the VPC
resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true  # auto-assign public IP

  tags = {
    Name = "llm-chat-subnet"
  }
}

# Internet Gateway - connects VPC to the internet
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "llm-chat-igw"
  }
}

# Route Table - tells traffic where to go
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"           # all traffic
    gateway_id = aws_internet_gateway.main.id  # goes to internet
  }

  tags = {
    Name = "llm-chat-rt"
  }
}

# Associate route table with subnet
resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

# Security Group - firewall rules
resource "aws_security_group" "main" {
  vpc_id = aws_vpc.main.id
  name   = "llm-chat-sg"

  # Allow SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow FastAPI app
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow Kubernetes API
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "llm-chat-sg"
  }
}

# EC2 Instance - your actual server
resource "aws_instance" "main" {
  ami                    = "ami-0faab6bdbac9486fb"  # Ubuntu 22.04 in eu-central-1
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.main.id]
  key_name               = aws_key_pair.main.key_name

  # Script that runs automatically when server starts
  user_data = templatefile("user_data.sh", {
    groq_api_key = var.groq_api_key
  })

  tags = {
    Name = "llm-chat-server"
  }
}

# SSH Key Pair - so you can SSH into the server
resource "aws_key_pair" "main" {
  key_name   = "llm-chat-key"
  public_key = file("~/.ssh/id_rsa.pub")  # uses your existing SSH key
}