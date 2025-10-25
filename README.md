# Terraform Kubernetes Infrastructure Repository

This repository contains Terraform configuration files to provision and manage all resources necessary for a fully functional Kubernetes cluster.

Currently includes these elements.
1. MetalLB
2. Nginx Ingress Controller
3. ArgoCD, connected to my homelab-argo repo
4. NFS mounts to my NAS
5. iSCSI driver
5. Vault with a vault autounseal cronjob

## How to prepare Terraform on the workstation

To get Terraform working, clone the repo and run 

```bash
cd k8s
terraform init -upgrade
```

## How to deploy
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

## Configure Vault & ArgoCD

Next we need to configure two things.
1. Vault auto-unseal
2. Vault configuration for ESO
3. Deploy ArgoCD

First we need to setup vault auto-unseal after reboot.
List the keys and unseal the vault manually for the first time

```bash
kubectl exec -n vault vault-0 -- vault operator init
kubectl exec -n vault vault-0 -- vault operator unseal [key1]
kubectl exec -n vault vault-0 -- vault operator unseal [key2]
kubectl exec -n vault vault-0 -- vault operator unseal [key3]
```

Save the keys into a password manager. After that we'll setup a kubernetes secret which will be used by a cronjob to unseal the vault.

```bash
kubectl create secret generic vault-unseal-keys -n vault \
  --from-literal=key1='<key1>' \
  --from-literal=key2='<key2>' \
  --from-literal=key3='<key3>'
```

(Make sure to remove that line from bash_history ;) )

Next, ensure vault.local resolves to 192.168.10.90 (either DNS or a manual host entry)

Move into the vault directory and run the terraform configs
```bash
cd vault/
terraform apply
```

Once it's all ready, you can deploy ArgoCD

```bash
cd argocd/
terraform apply/
```