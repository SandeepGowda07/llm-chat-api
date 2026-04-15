variable "aws_region" {
  default = "eu-central-1"
}

variable "instance_type" {
  default = "t3.micro"  # free tier
}

variable "groq_api_key" {
  description = "Groq API key"
  sensitive   = true  # won't show in logs
}