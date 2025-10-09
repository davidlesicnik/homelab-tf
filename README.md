# Terraform Kubernetes Infrastructure Repository

This repository contains Terraform configuration files to provision and manage all resources necessary for a fully functional Kubernetes cluster.

Currently includes two elements.
1. MetalLB
2. Nginx Ingress Controller

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