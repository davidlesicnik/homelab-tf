# Terraform Kubernetes Infrastructure Repository

This repository contains Terraform configuration files to provision and manage all resources necessary for a fully functional Kubernetes cluster.

Currently includes these elements.
1. MetalLB
2. Nginx Ingress Controller
3. ArgoCD, connected to my homelab-argo repo
4. NFS mount to my NAS

## How to prepare Terraform on the workstation

To get Terraform working, clone the repo and run 

```bash
terraform init -upgrade
```

## How to deploy the changes

To apply the terraform state, simply run
```bash
terraform plan
```

Check if the changes are OK, then run

```bash
terraform apply
```

Obtain ArgoCD admin user password
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```