# ============================================================
# Bootstrap — run ONCE before anything else.
# Creates the S3 bucket and DynamoDB table that the main
# Terraform config uses to store and lock its state.
#
# Uses LOCAL state (no backend) — this is intentional.
# Never run terraform destroy on this.
# ============================================================

provider "aws" {
  region = "eu-central-1"
}

# S3 bucket — stores terraform.tfstate for the main config.
# Must exist before you run terraform init in the parent folder.
resource "aws_s3_bucket" "tfstate" {
  bucket = "llm-chat-tfstate"

  # Prevent accidental deletion of the bucket that holds your state.
  # If you really want to delete it, remove this first.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name    = "llm-chat-tfstate"
    Purpose = "Terraform remote state"
  }
}

# Enable versioning — every time Terraform writes a new state,
# the old one is kept as a version. You can restore if state corrupts.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

output "bucket_name" {
  value = aws_s3_bucket.tfstate.bucket
}
