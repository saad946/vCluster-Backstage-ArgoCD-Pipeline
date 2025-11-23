#!/bin/bash

# Script to set up IAM Role for Service Account (IRSA) for EBS CSI Driver
# This fixes the EBS CSI driver CrashLoopBackOff issue

set -e

CLUSTER_NAME="${1:-vcluster-backstage-crossplane-demo}"
REGION="${2:-us-east-1}"
ACCOUNT_ID="${3:-982291412478}"

echo "Setting up EBS CSI Driver IRSA for cluster: $CLUSTER_NAME"

# Get OIDC issuer
OIDC_ISSUER=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query "cluster.identity.oidc.issuer" --output text | sed 's|https://||')
echo "OIDC Issuer: $OIDC_ISSUER"

# Check if OIDC provider exists
if ! aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?contains(Arn, '$OIDC_ISSUER')]" --output text | grep -q .; then
    echo "Creating OIDC provider..."
    aws iam create-open-id-connect-provider \
        --url https://$OIDC_ISSUER \
        --client-id-list sts.amazonaws.com \
        --thumbprint-list 9e99a48a9960b14926bb7f3b02e22da2b0ab7280
fi

# Create IAM role
ROLE_NAME="AmazonEKS_EBS_CSI_DriverRole_${CLUSTER_NAME}"
TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_ISSUER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_ISSUER}:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa",
          "${OIDC_ISSUER}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF
)

echo "Creating IAM role: $ROLE_NAME"
if aws iam get-role --role-name $ROLE_NAME &>/dev/null; then
    echo "Role already exists, updating trust policy..."
    aws iam update-assume-role-policy --role-name $ROLE_NAME --policy-document "$TRUST_POLICY"
else
    aws iam create-role \
        --role-name $ROLE_NAME \
        --assume-role-policy-document "$TRUST_POLICY" \
        --description "IRSA role for EBS CSI Driver on $CLUSTER_NAME"
fi

# Attach EBS CSI driver policy
POLICY_ARN="arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
echo "Attaching policy: $POLICY_ARN"
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn $POLICY_ARN

# Get role ARN
ROLE_ARN=$(aws iam get-role --role-name $ROLE_NAME --query 'Role.Arn' --output text)
echo ""
echo "✅ IAM Role created successfully!"
echo "Role ARN: $ROLE_ARN"
echo ""
echo "Next step: Apply the service account annotation manifest:"
echo "kubectl apply -f infrastructure/eks-ebs-csi/ebs-csi-sa-annotation.yaml"
echo ""
echo "Or annotate manually:"
echo "kubectl annotate serviceaccount ebs-csi-controller-sa -n kube-system eks.amazonaws.com/role-arn=$ROLE_ARN --overwrite"

