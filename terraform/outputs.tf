# The name of the EKS cluster — used in the CI/CD pipeline
# for: aws eks update-kubeconfig --name <cluster_name>
output "cluster_name" {
  value = aws_eks_cluster.main.name
}

# The API server endpoint — just for reference/debugging
output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}
