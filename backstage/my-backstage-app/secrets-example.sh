# Example secrets file - Copy this to secrets.sh and fill in your actual values
# This file is safe to commit to git

export GITHUB_TOKEN=your-github-token-here
export AUTH_GITHUB_CLIENT_ID=your-github-oauth-client-id
export AUTH_GITHUB_CLIENT_SECRET=your-github-oauth-client-secret
export K8S_CONFIG_CA_DATA=your-k8s-ca-data-here
export K8S_SA_TOKEN=your-k8s-service-account-token
export GOOGLE_APPLICATION_CREDENTIALS=./google-creds.json
export AUTH_GOOGLE_CLIENT_ID=your-google-oauth-client-id
export AUTH_GOOGLE_CLIENT_SECRET=your-google-oauth-client-secret
export ARGOCD_AUTH_TOKEN=your-argocd-api-token-here
export admin_password=your-postgres-admin-password
export user_password=your-postgres-user-password
export replication_password=your-postgres-replication-password
yarn dev

