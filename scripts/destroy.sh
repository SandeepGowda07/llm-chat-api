#!/bin/bash
# ============================================================
# destroy.sh — safely tear down everything in the right order
#
# Why this order matters:
#   Kubernetes creates AWS resources (ELB, Security Groups, ENIs)
#   that Terraform doesn't know about. If you run terraform destroy
#   first, it fails because those resources still live inside the VPC.
#
# Correct order:
#   1. Delete k8s resources → AWS cleans up ELB + Security Groups
#   2. Wait for ELB to disappear
#   3. terraform destroy → VPC is now empty, deletes cleanly
# ============================================================

set -e   # exit immediately if any command fails

echo "WARNING: This will destroy ALL infrastructure."
echo "To pause cheaply instead, scale nodes to 0:"
echo "  aws eks update-nodegroup-config --cluster-name llm-chat-cluster \\"
echo "    --nodegroup-name llm-chat-cluster-nodes \\"
echo "    --scaling-config minSize=0,maxSize=2,desiredSize=0 \\"
echo "    --region eu-central-1"
echo ""
read -p "Type 'yes' to proceed with full destroy: " confirm
if [ "$confirm" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

REGION="eu-central-1"
CLUSTER_NAME="llm-chat-cluster"

echo "==> Step 1: Configure kubectl to talk to EKS"
aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME

echo ""
echo "==> Step 2: Uninstall Helm release"
echo "    This deletes the Kubernetes Service, which tells AWS to delete the ELB"
helm uninstall llm-chat-api || echo "Helm release not found, skipping"

echo ""
echo "==> Step 3: Wait for ELB to be fully deleted by AWS (~1-2 min)"
echo "    Waiting for service external IP to clear..."
for i in $(seq 1 24); do
  ELB=$(kubectl get svc llm-chat-api-service \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
  if [ -z "$ELB" ]; then
    echo "    ELB is gone."
    break
  fi
  echo "    Still waiting... ($((i * 5))s)"
  sleep 5
done

echo ""
echo "==> Step 4: Run terraform destroy"
cd "$(dirname "$0")/../terraform"
terraform destroy

echo ""
echo "==> Done. All resources destroyed."
echo "    S3 state bucket and DynamoDB table still exist (run bootstrap/destroy if needed)"
