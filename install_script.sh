# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
 
# Install Crossplane
helm repo add crossplane-stable \
    https://charts.crossplane.io/stable
helm repo update
helm upgrade --install crossplane crossplane-stable/crossplane \
    --namespace crossplane-system --create-namespace \
    --set image.tag=v2.2.0-rc.0.23.gc28c7859b \
    --wait

# Wait for Crossplane to be ready
echo "Waiting for Crossplane to be ready..."
kubectl wait --for=condition=Available deployment/crossplane \
    -n crossplane-system --timeout=300s

cd ./crossplane

# Apply Crossplane providers (now using DeploymentRuntimeConfig for Crossplane 2.2+)
echo "Installing Crossplane providers..."
kubectl apply -f ./providers/

# Wait for providers to be installed and healthy
echo "Waiting for providers to be installed..."
kubectl wait --for=condition=Installed provider.pkg.crossplane.io \
    --all --timeout=300s || true

echo "Waiting for providers to be healthy..."
kubectl wait --for=condition=Healthy provider.pkg.crossplane.io \
    --all --timeout=600s || echo "Some providers may still be starting..."

sleep 5

kubectl apply -f ./provider-configs/
kubectl apply -f xrds.yaml
kubectl apply -f compositions.yaml

# Install Backstage
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add backstage https://backstage.github.io/charts
kubectl create ns backstage

