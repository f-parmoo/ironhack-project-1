## Kubernetes Deployment on Amazon EKS

This project is deployed on an Amazon EKS cluster using Kubernetes, Kustomize overlays, and NGINX Ingress.

### Architecture

The application consists of the following services:

* `vote`: Python frontend for voting
* `result`: Node.js frontend for displaying results
* `worker`: .NET worker that processes votes
* `redis`: message queue
* `postgres`: database with persistent storage

The project uses a Kustomize-based structure with separate environments:

```text
k8s/
├── base/
└── overlays/
    ├── staging/
    └── production/
```

External traffic is routed through NGINX Ingress.

Example domains:

### Staging

* `http://vote.staging.fatemeh.ironlabs.online`
* `http://result.staging.fatemeh.ironlabs.online`

### Production

* `http://vote.fatemeh.ironlabs.online`
* `http://result.fatemeh.ironlabs.online`

---

## Prerequisites

Make sure you have the following installed and configured:

* AWS CLI
* kubectl
* eksctl
* Helm
* Docker
* Access to an existing EKS cluster
* kubeconfig configured for the cluster

Check cluster access:

```bash
kubectl get nodes
```

---

## Install AWS EBS CSI Driver

This project uses a PersistentVolumeClaim (PVC) for PostgreSQL storage.

To allow Kubernetes to dynamically provision AWS EBS volumes, install the AWS EBS CSI Driver and attach the required IAM permissions.

Install the EBS CSI Driver addon:

```bash
eksctl create addon \
  --name aws-ebs-csi-driver \
  --cluster <your-cluster-name> \
  --region <your-region>
```

Attach the required IAM policy to your EKS node group role:

```bash
aws iam attach-role-policy \
  --role-name <your-node-instance-role> \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy
```

Verify the CSI driver is running:

```bash
kubectl get pods -n kube-system
```

You should see pods similar to:

```text
ebs-csi-controller
ebs-csi-node
```

---

## Install NGINX Ingress Controller

Add the Helm repository:

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
```

Install NGINX Ingress Controller:

```bash
helm install my-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace
```

Make the Load Balancer internet-facing:

```bash
helm upgrade my-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"=internet-facing
```

Check the Load Balancer DNS:

```bash
kubectl get svc -n ingress-nginx
```

---

## Kubernetes Secrets

For local development and testing, create a `secret.yaml` file from the provided sample:

```bash
cp k8s/base/secret-sample.yaml k8s/base/secret.yaml
```

Edit the secret values if needed.

The real `secret.yaml` file is ignored by Git and should never be committed.

---

## DNS Setup

Create Route53 DNS records pointing to the NGINX Ingress Load Balancer.

Example:

```text
vote-staging.yourname.ironlabs.online   -> <NGINX_LOAD_BALANCER_DNS>
result-staging.yourname.ironlabs.online -> <NGINX_LOAD_BALANCER_DNS>

vote.yourname.ironlabs.online           -> <NGINX_LOAD_BALANCER_DNS>
result.yourname.ironlabs.online         -> <NGINX_LOAD_BALANCER_DNS>
```

Get the Load Balancer DNS:

```bash
kubectl get svc -n ingress-nginx
```

Example output:

```text
k8s-ingressn-mynginxi-xxxxxxxx.elb.us-east-1.amazonaws.com
```

Use this value as the DNS target.

---

## Deploy the Application

### Create Namespaces

Namespaces must be created before applying the overlays.

### Staging

```bash
kubectl apply -f k8s/overlays/staging/namespace.yaml
```

### Production

```bash
kubectl apply -f k8s/overlays/production/namespace.yaml
```

---

## Deploy with Kustomize

### Staging

```bash
kubectl apply -k k8s/overlays/staging
```

### Production

```bash
kubectl apply -k k8s/overlays/production
```

---

## Verify Deployment

### Check pods

```bash
kubectl get pods -n staging
kubectl get pods -n production
```

### Check services

```bash
kubectl get svc -n staging
kubectl get svc -n production
```

### Check ingress

```bash
kubectl get ingress -n staging
kubectl get ingress -n production
```

### Check PVC

```bash
kubectl get pvc -n staging
kubectl get pvc -n production
```

---

## Kustomize Structure

### Base

Shared Kubernetes manifests:

```text
k8s/base/
```

### Overlays

Environment-specific configuration:

```text
k8s/overlays/staging/
k8s/overlays/production/
```

Environment differences are managed using patches, including:

* Ingress hosts
* Resource requests and limits
* Replicas
* Readiness and liveness probes
* Config overrides

---

## Access the Application

### Staging

```text
http://vote.staging.fatemeh.ironlabs.online
http://result.staging.fatemeh.ironlabs.online
```

### Production

```text
http://vote.fatemeh.ironlabs.online
http://result.fatemeh.ironlabs.online
```

---

## Notes

For demo purposes, Kubernetes Secrets are used for database credentials.

In a production environment, secrets should be managed using a more secure solution such as:

* GitHub Actions Secrets
* AWS Secrets Manager
* External Secrets Operator
* HashiCorp Vault
