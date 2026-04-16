# LLM Chat API — Cloud-Native Deployment on AWS EKS

A production-grade REST API built with FastAPI and deployed on AWS EKS using a fully automated CI/CD pipeline. The project covers the complete cloud engineering lifecycle — from local development to infrastructure provisioning, containerisation, Kubernetes orchestration, and automated deployment.

---

## Architecture

```
Developer
    │
    │  git push
    ▼
GitHub Actions
    ├── pytest (unit tests + coverage)
    ├── Trivy (container security scan)   ← run in parallel
    ├── Docker build + push to Docker Hub
    └── Helm deploy to AWS EKS
                │
                ▼
        AWS EKS Cluster
        ┌───────────────────────────────┐
        │  VPC (eu-central-1)           │
        │  ├── Subnet AZ-a              │
        │  ├── Subnet AZ-b              │
        │  └── EKS Node Group           │
        │       └── Pod: llm-chat-api   │
        │            └── FastAPI app    │
        └───────────────────────────────┘
                │
                │  AWS Load Balancer (ELB)
                ▼
        Public Internet
        GET  /health
        POST /chat  →  Groq API (llama-3.3-70b)
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| API | Python, FastAPI, Pydantic |
| LLM | Groq API — llama-3.3-70b-versatile |
| Containerisation | Docker, Docker Hub |
| Kubernetes | AWS EKS, Helm |
| Infrastructure as Code | Terraform |
| Cloud | AWS (EKS, VPC, IAM, ELB, S3) |
| CI/CD | GitHub Actions |
| Testing | pytest, pytest-cov |
| Security | Trivy container scanning |

---

## API Endpoints

| Method | Endpoint | Description |
|---|---|---|
| GET | `/` | App info and version |
| GET | `/health` | Health check |
| POST | `/chat` | Send a prompt, get LLM response |

**Example:**
```bash
curl -X POST http://<your-elb-hostname>/chat \
  -H "Content-Type: application/json" \
  -d '{"prompt": "What is Kubernetes in one sentence?"}'

# Response
{
  "response": "Kubernetes is an open-source container orchestration platform...",
  "model": "llama-3.3-70b-versatile"
}
```

---

## CI/CD Pipeline

Two separate pipelines — app and infrastructure are kept independent.

### Application Pipeline (`ci-cd.yml`)
Triggers on every push to `main` (ignores `terraform/` changes).

```
test ──┐
       ├──► build & push image ──► helm deploy to EKS
scan ──┘
```

| Job | What it does |
|---|---|
| **test** | Runs pytest with coverage report |
| **scan** | Builds image locally, scans for CVEs with Trivy |
| **build** | Builds Docker image, pushes with `latest` + SHA tag |
| **deploy** | Configures kubectl via AWS CLI, deploys with Helm |

### Infrastructure Pipeline (`infra.yml`)
Triggers only when `terraform/` files change.

```
terraform plan ──► manual approval ──► terraform apply
```

---

## Project Structure

```
llm-chat-api/
├── app/
│   └── main.py                  FastAPI application
├── tests/
│   └── test_main.py             pytest unit tests
├── helm/
│   └── llm-chat-api/
│       ├── Chart.yaml           Helm chart metadata
│       ├── values.yaml          Default values (image, resources, probes)
│       └── templates/
│           ├── deployment.yaml  Kubernetes Deployment template
│           └── service.yaml     Kubernetes Service (LoadBalancer)
├── terraform/
│   ├── bootstrap/
│   │   └── main.tf              Creates S3 bucket for remote state (run once)
│   ├── backend.tf               S3 remote state configuration
│   ├── main.tf                  EKS cluster, VPC, subnets, IAM roles
│   ├── variables.tf
│   └── outputs.tf
├── .github/
│   └── workflows/
│       ├── ci-cd.yml            Application pipeline
│       └── infra.yml            Infrastructure pipeline
├── scripts/
│   └── destroy.sh               Safe teardown script
└── Dockerfile
```

---

## Local Development

**Prerequisites:** Python 3.10+, Docker, AWS CLI, kubectl, Helm, Terraform

```bash
# Clone
git clone https://github.com/SandeepGowda07/llm-chat-api.git
cd llm-chat-api

# Run locally
pip install -r requirements.txt
GROQ_API_KEY=your-key uvicorn app.main:app --reload --port 8000

# Run tests
pytest tests/ -v --cov=app

# Run in Docker
docker build -t llm-chat-api .
docker run -p 8000:8000 -e GROQ_API_KEY=your-key llm-chat-api
```

---

## Infrastructure Setup

### 1 — Bootstrap (one time only)
```bash
cd terraform/bootstrap
terraform init
terraform apply
# Creates S3 bucket for remote Terraform state
```

### 2 — Provision EKS cluster (~15 min)
```bash
cd terraform
terraform init
terraform apply
```

### 3 — Add GitHub Secrets
| Secret | Description |
|---|---|
| `AWS_ACCESS_KEY_ID` | AWS credentials |
| `AWS_SECRET_ACCESS_KEY` | AWS credentials |
| `DOCKER_USERNAME` | Docker Hub username |
| `DOCKER_PASSWORD` | Docker Hub access token |
| `GROQ_API_KEY` | Groq API key |

### 4 — Deploy
```bash
git push origin main
# GitHub Actions handles the rest
```

---

## Teardown

```bash
# Scale down nodes when not in use (saves ~$2.90/day, 3 min to resume)
aws eks update-nodegroup-config \
  --cluster-name llm-chat-cluster \
  --nodegroup-name llm-chat-cluster-nodes \
  --scaling-config minSize=0,maxSize=2,desiredSize=0 \
  --region eu-central-1

# Full destroy (deletes everything)
./scripts/destroy.sh
```

---

## Key Design Decisions

**Why EKS over plain EC2?** Managed control plane, auto node recovery, AWS-native load balancing — closer to real production environments.

**Why Helm over raw kubectl apply?** Templates avoid hardcoding image tags in YAML files. The CI/CD pipeline passes the exact SHA tag at deploy time — no file modification needed.

**Why two separate pipelines?** Infrastructure changes (Terraform) are infrequent and risky — they require a manual approval gate. Application deploys are frequent and safe to automate. Mixing them creates unnecessary risk.

**Why remote Terraform state?** GitHub Actions runners are ephemeral — local state is lost after every run. S3 remote state persists across runs and prevents the "resource already exists" errors caused by Terraform losing track of what it created.
