# EBS CSI Driver IRSA Fix

This directory contains fixes for the EBS CSI Driver IRSA (IAM Role for Service Account) issue that causes the EBS CSI controller pods to crash.

## Problem

The EBS CSI driver controller pods fail with:
```
no EC2 IMDS role found
failed to refresh cached credentials
```

This happens because the EBS CSI driver service account doesn't have an IAM role attached.

## Solution Options

### Option 1: Manual Fix (Quick)

Run the setup script to create the IAM role and annotate the service account:

```bash
# Make script executable
chmod +x infrastructure/eks-ebs-csi/setup-ebs-csi-irsa.sh

# Run the script (defaults to vcluster-backstage-crossplane-demo in us-east-1)
./infrastructure/eks-ebs-csi/setup-ebs-csi-irsa.sh

# Or specify cluster name and region
./infrastructure/eks-ebs-csi/setup-ebs-csi-irsa.sh <cluster-name> <region> <account-id>
```

Then apply the service account annotation:
```bash
kubectl apply -f infrastructure/eks-ebs-csi/ebs-csi-sa-annotation.yaml
```

### Option 2: Via ArgoCD (GitOps)

1. **Create IAM Role** (one-time setup):
   ```bash
   chmod +x infrastructure/eks-ebs-csi/setup-ebs-csi-irsa.sh
   ./infrastructure/eks-ebs-csi/setup-ebs-csi-irsa.sh
   ```

2. **Commit the manifest to your repo** (already done if you see this file)

3. **Create ArgoCD Application** to sync this manifest:
   ```bash
   argocd app create ebs-csi-irsa \
     --repo <your-repo-url> \
     --path infrastructure/eks-ebs-csi \
     --dest-server https://9F4924FC7DD5C3A7B2202693D9F55514.gr7.us-east-1.eks.amazonaws.com \
     --dest-namespace kube-system \
     --project default \
     --sync-policy automated \
     --grpc-web \
     --insecure
   ```

### Option 3: Via Crossplane (Infrastructure as Code)

Use Crossplane to manage the IAM role and service account annotation. See `crossplane-ebs-csi-irsa.yaml` for the Crossplane manifest.

## Verification

After applying the fix, verify:

```bash
# Check EBS CSI controller pods
kubectl get pods -n kube-system | grep ebs-csi-controller

# Check service account annotation
kubectl get sa ebs-csi-controller-sa -n kube-system -o yaml | grep role-arn

# Check PVCs can be created
kubectl get pvc -A
```

## Files

- `setup-ebs-csi-irsa.sh` - Script to create IAM role and set up IRSA
- `ebs-csi-sa-annotation.yaml` - Kubernetes manifest to annotate service account
- `crossplane-ebs-csi-irsa.yaml` - Crossplane manifest for GitOps approach

