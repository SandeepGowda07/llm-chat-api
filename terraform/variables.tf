variable "aws_region" {
  default = "eu-central-1"
}

variable "cluster_name" {
  default = "llm-chat-cluster"
}

# t3.small is the minimum recommended for EKS worker nodes.
# t3.micro often runs out of memory because k8s system pods
# (kube-proxy, aws-node, coredns) consume ~300MB before your app even starts.
variable "instance_type" {
  default = "t3.small"
}
