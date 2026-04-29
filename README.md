<!-- © 2026 | Ironhack -->

---

# Multi-Stack Voting Application

**Welcome to your DevOps practice project!** This repository hosts a multi-stack voting application composed of several services, each implemented in a different language and technology stack. The goal is to help you gain experience with containerization, orchestration, and running a distributed set of services—both individually and as part of a unified system.

This application, while simple, uses multiple components commonly found in modern distributed architectures, giving you hands-on practice in connecting services, handling containers, and working with basic infrastructure automation.

## Application Overview

The voting application includes:

- **Vote (Python)**: A Python Flask-based web application where users can vote between two options.
- **Redis (in-memory queue)**: Collects incoming votes and temporarily stores them.
- **Worker (.NET)**: A .NET 7.0-based service that consumes votes from Redis and persists them into a database.
- **Postgres (Database)**: Stores votes for long-term persistence.
- **Result (Node.js)**: A Node.js/Express web application that displays the vote counts in real time.

### Why This Setup?

The goal is to introduce you to a variety of languages, tools, and frameworks in one place. This is **not** a perfect production design. Instead, it’s intentionally diverse to help you:

- Work with multiple runtimes and languages (Python, Node.js, .NET).
- Interact with services like Redis and Postgres.
- Containerize applications using Docker.
- Use Docker Compose to orchestrate and manage multiple services together.

By dealing with this “messy” environment, you’ll build real-world problem-solving skills. After this project, you should feel more confident tackling more complex deployments and troubleshooting issues in containerized, multi-service setups.

---

## How to Run Each Component

### Running the Vote Service (Python) Locally (No Docker)

1. Ensure you have Python 3.10+ installed.
2. Navigate to the `vote` directory:
   ```bash
   cd services/vote
   pip install -r requirements.txt
   python app.py
   ```
   Access the vote interface at [http://localhost:5000](http://localhost:5000).

### Running Redis Locally (No Docker)

1. Install Redis on your system ([https://redis.io/docs/getting-started/](https://redis.io/docs/getting-started/)).
2. Start Redis:
   ```bash
   redis-server
   ```
   Redis will be available at `localhost:6379`.

### Running the Worker (C#/.NET) Locally (No Docker)

1. Ensure .NET 7.0 SDK is installed.
2. Navigate to `worker`:
   ```bash
   cd services/worker
   dotnet restore
   dotnet run
   ```
   The worker will attempt to connect to Redis and Postgres when available.

### Running Postgres Locally (No Docker)

1. Install Postgres from [https://www.postgresql.org/download/](https://www.postgresql.org/download/).
2. Start Postgres, note the username and password (default `postgres`/`postgres`):
   ```bash
   # On many systems, Postgres runs as a service once installed.
   ```
   Postgres will be available at `localhost:5432`.

### Running the Result Service (Node.js) Locally (No Docker)

1. Ensure Node.js 18+ is installed.
2. Navigate to `result`:
   ```bash
   cd services/result
   npm install
   node server.js
   ```
   Access the results interface at [http://localhost:4000](http://localhost:4000).

**Note:** To get the entire system working end-to-end (i.e., votes flowing through Redis, processed by the worker, stored in Postgres, and displayed by the result app), you’ll need to ensure each component is running and that connection strings or environment variables point to the correct services.

---

## Running the Entire Stack in Docker

### Building and Running Individual Services

You can build each service with Docker and run them individually:

- **Vote (Python)**:
  ```bash
  docker build -t myorg/vote:latest ./vote
  docker run --name vote -p 8080:80 myorg/vote:latest
  ```
  Visit [http://localhost:8080](http://localhost:8080).

- **Redis** (official image, no build needed):
  ```bash
  docker run --name redis -p 6379:6379 redis:alpine
  ```

- **Worker (.NET)**:
  ```bash
  docker build -t myorg/worker:latest ./worker
  docker run --name worker myorg/worker:latest
  ```
  
- **Postgres**:
  ```bash
  docker run --name db -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -p 5432:5432 postgres:15-alpine
  ```

- **Result (Node.js)**:
  ```bash
  docker build -t myorg/result:latest ./result
  docker run --name result -p 8081:80 myorg/result:latest
  ```
  Visit [http://localhost:8081](http://localhost:8081).

### Using Docker Compose

The easiest way to run the entire stack is via Docker Compose. From the project root directory:

```bash
docker compose up
```

This will:

- Build and run the vote, worker, and result services.
- Run Redis and Postgres from their official images.
- Set up networks, volumes, and environment variables so all services can communicate.

Visit [http://localhost:8080](http://localhost:8080) to vote and [http://localhost:8081](http://localhost:8081) to see results.

---

## Notes on Platforms (arm64 vs amd64)

If you’re on an arm64 machine (e.g., Apple Silicon M1/M2) and encounter issues with images or dependencies that assume amd64, you can use Docker `buildx`:

```bash
docker buildx build --platform linux/amd64 -t myorg/worker:latest ./worker
```

This ensures the image is built for the desired platform.

---


## 🌍 Terraform Setup

This project supports two infrastructure approaches:

1. `single-az`
2. `multi-az`

The `single-az` setup is a simpler architecture where all core resources are deployed in one Availability Zone.

The `multi-az` setup is designed for higher availability. In this architecture, public and private subnets are created across multiple Availability Zones, the frontend runs behind a load balancer, backend instances can be distributed across AZs, and the database is managed by **Amazon Aurora**, which provides database replication and improved availability.

---

### 🧱 Terraform Directory Structure

```text
terraform/
  single-az/
    bootstrap/
    infra/

  multi-az/
    bootstrap/
    infra/
```

Each approach has two Terraform parts:

- bootstrap
- infra

You must apply the bootstrap configuration first.
The bootstrap step creates the S3 bucket and DynamoDB table used for storing and locking the Terraform remote state.

---
### 🧱 Bootstrap Terraform Backend

For the single-az setup:
```
cd terraform/single-az/bootstrap
terraform init
terraform plan
terraform apply
```

For the multi-az setup:
```
cd terraform/multi-az/bootstrap
terraform init
terraform plan
terraform apply
```
This will create:

- An S3 bucket for Terraform state
- S3 bucket versioning
- Server-side encryption
- Public access blocking
- A DynamoDB table for Terraform state locking

---
### 📌 Terraform Remote State

The infra configuration uses the S3 backend created in the bootstrap step:
```
terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket         = "voting-project-tf-state-bucket"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "voting-project-tf-state-lock"
  }
}
```
Make sure the backend bucket and DynamoDB table names match the resources created by the corresponding bootstrap configuration.

---
### 🏗️ Deploy Infrastructure

After the bootstrap step is completed, deploy the infrastructure.

single-az setup:
```
cd terraform/single-az/infra
terraform init
terraform plan
terraform apply
terraform output -raw ansible_inventory > ../../../ansible/single-az/hosts.ini
```

multi-az setup:
```
cd terraform/multi-az/infra
terraform init
terraform plan
terraform apply
```


---

## ⚙️ Ansible Setup

### 🧱 Single-AZ

#### 📄 Inventory
The `hosts.ini` file is generated automatically using Terraform outputs:

```bash
cd terraform/single-az/infra
terraform output -raw ansible_inventory > ../../../ansible/single-az/hosts.ini
```
#### 🐳 Install Docker
ansible-playbook -i ansible/single-az/hosts.ini ansible/single-az/install_docker.yaml
#### 📦 Deploy Containers
ansible-playbook -i ansible/single-az/hosts.ini ansible/single-az/deploy_containers.yaml
#### 🌐 Access the Application
```
Vote app:   http://<FRONTEND_PUBLIC_IP>:8080
Result app: http://<FRONTEND_PUBLIC_IP>:8081
```
---
### 🏗️ Multi-AZ
#### 🔑 Terraform Outputs Required by Ansible

In the multi-az setup, Terraform outputs two important values:
```
output "aurora_endpoint" {
  value = aws_rds_cluster.postgres.endpoint
}

output "redis_endpoint" {
  value = aws_lb.backend.dns_name
}
```
After running Terraform:

terraform output

or:

terraform output -raw aurora_endpoint
terraform output -raw redis_endpoint

Copy these values into:
```
ansible/multi-az/group_vars/all.yml
```
Example:
```
aurora_endpoint: voting-project-ha-aurora.cluster-xxxxxx.us-east-1.rds.amazonaws.com
redis_endpoint: voting-project-ha-backend-lb-xxxxxx.elb.us-east-1.amazonaws.com
```
These variables are used by the containers:

- aurora_endpoint is used by the worker and result services to connect to Aurora PostgreSQL.
- redis_endpoint is used by the vote service to connect to Redis through the internal Network Load Balancer.

Aurora requires SSL connections, so the application containers use: PGSSLMODE=require


#### 📄 Inventory

You must manually update the inventory file with your infrastructure details:
```
ansible/multi-az/hosts.ini
```
#### 🐳 Install Docker
```
ansible-playbook -i ansible/multi-az/hosts.ini ansible/multi-az/install_docker.yaml
```
#### 📦 Deploy Containers
```
ansible-playbook -i ansible/multi-az/hosts.ini ansible/multi-az/deploy_containers.yaml
```
#### 🌐 Access the Application
```
Vote app:   http://<ALB_DNS_NAME>:8080
Result app: http://<ALB_DNS_NAME>:8081
```

---

## 🏛️ Architecture Notes
#### Single-AZ

The single-az architecture includes:

- One VPC
- One public subnet
- One private subnet
- One frontend EC2 instance in the public subnet
- Backend and database EC2 instances in the private subnet
- NAT Gateway for private subnet outbound access


#### Multi-AZ

The multi-az architecture improves availability by using:

- Public subnets across multiple Availability Zones
- Private subnets across multiple Availability Zones
- Application Load Balancer for frontend traffic
- Frontend instances distributed across private subnets
- Backend instances designed to run across multiple AZs
- Amazon Aurora for the PostgreSQL database layer

Aurora is used instead of a manually managed PostgreSQL EC2 instance because it provides managed replication, automated failover capabilities, and better availability for the database layer.