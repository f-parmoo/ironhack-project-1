## Kubernetes Deployment on Amazon EKS

This project is deployed on an Amazon EKS cluster using Kubernetes manifests.

### Architecture

The application consists of the following services:

- `vote`: Python frontend for voting
- `result`: Node.js frontend for displaying results
- `worker`: .NET worker that processes votes
- `redis`: message queue
- `postgres`: database with persistent storage

External traffic is routed through NGINX Ingress:

- `http://vote.fatemeh.ironlabs.online`
- `http://result.fatemeh.ironlabs.online`

---

## Prerequisites

Make sure you have the following installed and configured:

- AWS CLI
- kubectl
- eksctl
- Helm
- Docker
- Access to an existing EKS cluster
- kubeconfig configured for the cluster

Check cluster access:

```bash
kubectl get nodes
```

---

## Install AWS EBS CSI Driver

This project uses a PersistentVolumeClaim (PVC) for PostgreSQL storage.  
To allow Kubernetes to dynamically provision AWS EBS volumes, you must install the AWS EBS CSI Driver and attach the required IAM permissions.

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

You can find your node instance role using:

```bash
aws iam list-roles
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

Without the EBS CSI Driver and IAM permissions, PostgreSQL PVCs may remain in the `Pending` state because Kubernetes cannot provision EBS volumes automatically.

---
## Install NGINX Ingress Controller

Add the Helm repo:
```
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
```
Install NGINX Ingress Controller:
```
helm install my-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace
```
Make the Load Balancer internet-facing:
```
helm upgrade my-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"=internet-facing
```
Check the Load Balancer DNS:
```
kubectl get svc -n ingress-nginx
```
---

## Kubernetes Secrets

For local development and testing, create a `secret.yaml` file from the provided sample:

```bash
cp secret-sample.yaml secret.yaml
```
Then edit the secret values if needed and apply it:

kubectl apply -f secret.yaml

The real secret.yaml file is ignored by Git and should never be committed.
---

## DNS Setup

Create your own Route53 CNAME records pointing to the NGINX Ingress Load Balancer.

Example:

```
vote.yourname.ironlabs.online   -> <NGINX_LOAD_BALANCER_DNS>
result.yourname.ironlabs.online -> <NGINX_LOAD_BALANCER_DNS>
```
You can find the Load Balancer DNS using:
```
kubectl get svc -n ingress-nginx
```
Example output:
```
k8s-ingressn-mynginxi-xxxxxxxx.elb.us-east-1.amazonaws.com
```
Use this value as the CNAME target.

Update ingress.yaml

Before applying the ingress manifest, update the host values inside ui-ingress.yaml:
```
rules:
  - host: vote.yourname.ironlabs.online
  - host: result.yourname.ironlabs.online
```
Then apply the ingress:
```
kubectl apply -f ingress.yaml
```
---
## Deploy the Application

Apply the Kubernetes manifests:
```
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/redis.yaml
kubectl apply -f k8s/postgres.yaml
kubectl apply -f k8s/worker.yaml
kubectl apply -f k8s/vote.yaml
kubectl apply -f k8s/result.yaml
kubectl apply -f k8s/ingress.yaml
```
Verify Deployment

Check pods:
```
kubectl get pods

Check services:

kubectl get svc
```
Check ingress:
```
kubectl get ingress
```
Check PVC:
```
kubectl get pvc
```
---
## Access the Application

Vote app:
```
http://vote.fatemeh.ironlabs.online
```
Result app:
```
http://result.fatemeh.ironlabs.online
```
---
## Notes

For demo purposes, Kubernetes Secrets are used for database credentials.

In a production environment, secrets should be managed using a more secure solution such as:

GitHub Actions Secrets
AWS Secrets Manager
External Secrets Operator
HashiCorp Vault