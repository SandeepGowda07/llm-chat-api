# Print the server's public IP after terraform apply
output "server_ip" {
  value       = aws_instance.main.public_ip
  description = "Public IP of the EC2 instance"
}