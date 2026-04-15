terraform {
  backend "s3" {
    bucket       = "llm-chat-tfstate"    # S3 bucket (created by bootstrap)
    key          = "terraform.tfstate"   # file path inside the bucket
    region       = "eu-central-1"
    use_lockfile = true                  # S3 native locking (no DynamoDB needed)
    encrypt      = true                  # encrypt state at rest
  }
}
