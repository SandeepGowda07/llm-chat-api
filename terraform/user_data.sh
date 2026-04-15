#!/bin/bash
# This script runs automatically when the EC2 server starts

# Update the system
apt-get update -y

# Create a 2GB swapfile (prevents OOM kills on small EC2 instances)
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab   # persist across reboots

# Install k3s (lightweight Kubernetes)
curl -sfL https://get.k3s.io | sh -

# Wait for k3s to be ready
sleep 30

# Store the Groq API key as a Kubernetes secret
k3s kubectl create secret generic groq-secret \
  --from-literal=GROQ_API_KEY=${groq_api_key}

echo "Server setup complete!"
