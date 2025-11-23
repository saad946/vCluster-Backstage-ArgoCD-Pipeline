# Overview

This repo is used for demoing vCluster in a Platform Engineering Playground. Tools used are:

- ArgoCD
- Crossplane
- Backstage
- AWS
- GCP
- GitHub Actions
- vClusters

You can run this playground in your own environment or request a K8s cluster from the Platform Engineering Playground on TeKanAid Academy. Either way, make sure to fork this repo to have full control over it. You will need this for ArgoCD among other things.

Once you have a running K8s cluster you can proceed to install the script below.

Run the `install_script.sh` to install ArgoCD and Crossplane. It will also get Backstage ready. You'll need to create a few more configurations before running Backstage.

## ArgoCD

### Access ArgoCD

#### Login to the UI
To access ArgoCD, you will need the initial admin password. You can get it using the command below:

```bash
kubectl get secret -n argocd argocd-initial-admin-secret -o json | jq -r '.data.password' | base64 --decode
```

And then use the username admin with this password to log in to ArgoCD.

You can port forward the service like this:

```bash
kubectl port-forward -n argocd service/argocd-server 8080:443
```

#### Login to the CLI

```bash
argocd login 127.0.0.1:8080 --username admin --password $(kubectl get secret -n argocd argocd-initial-admin-secret -o json | jq -r '.data.password' | base64 --decode) --grpc-web --insecure
```

#### Use ngrok for GitHub to connect to ArgoCD

When Backstage creates a new GitHub repo, we need to get GitHub actions to create an ArgoCD app that monitors this new GitHub repo. We need to expose our local ArgoCD instance to the internet so that GitHub can connect to it. We will use ngrok for this. In production, you would use an ingress in your cluster with a domain name and DNS configured.

First, [sign up](https://dashboard.ngrok.com/signup) for a free ngrok account and get an authtoken

1. Add authtoken
```bash
brew install ngrok/ngrok/ngrok
ngrok config add-authtoken cr_35ccAvcJRXfqqJZaWp4r8tx1n8P
```

2. Start a tunnel

**Option A: Manual Setup (Simple)**
```bash
# Start port-forward in background
kubectl port-forward -n argocd service/argocd-server 8080:443 > /tmp/argocd-pf.log 2>&1 &

# Start ngrok tunnel in background
ngrok http https://localhost:8080 > /tmp/ngrok.log 2>&1 &

# Wait a few seconds, then get the public URL
sleep 5
curl -s http://localhost:4040/api/tunnels | grep -o 'https://[a-z0-9-]*\.ngrok[^"]*' | head -1
```

**Option B: Automated Setup (Recommended)**
```bash
# Start both port-forward and ngrok in one command
kubectl port-forward -n argocd service/argocd-server 8080:443 & \
ngrok http https://localhost:8080 & \
sleep 8 && \
curl -s http://localhost:4040/api/tunnels | grep -o 'https://[a-z0-9-]*\.ngrok[^"]*' | head -1 | sed 's|https://||'
```

You'll get something like this:
```bash
Forwarding                    https://a7eb-24-150-170-114.ngrok-free.app -> https://localhost:8080
```

The `https://a7eb-24-150-170-114.ngrok-free.app` address is your ngrok forwarding address. **Important:** For GitHub secrets, use only the hostname (without `https://`), e.g., `a7eb-24-150-170-114.ngrok-free.app`.

**Note:** The ngrok URL changes each time you restart the tunnel. You'll need to update the `ARGOCD_SERVER` GitHub secret whenever you restart ngrok.

**To stop the tunnel:**
```bash
pkill -f "kubectl port-forward.*argocd-server"
pkill -f "ngrok http"
```

**To view ngrok web interface:**
Open http://localhost:4040 in your browser to see tunnel status and requests.

### Get an ArgoCD Token for Backstage Plugin

To allow Backstage to interact with ArgoCD, you'll need to generate an ArgoCD API token. You can do this by running the following command:

#### Allow admin account to create API tokens

First wee need to allow the admin account to create API tokens. We can do this by editing the `argocd-cm` ConfigMap and adding the following:

```bash
kubectl patch -n argocd configmap argocd-cm --type merge -p '{"data":{"accounts.admin":"apiKey"}}'
```

#### Generate the Token

Now you can generate an API token by running the command:
```bash
argocd account generate-token
```

or directly from the UI under `settings > accounts`

Now take this token and put in the Backstage `secrets.sh` file that you will create later in the Backstage section. It will look something like this:

```bash
export ARGOCD_AUTH_TOKEN=
```

## Update GitHub Actions Workflow

In the `.github/workflows/deploy_with_argocd.yaml` workflow file we do the following: 

1. Install the Argo CD CLI
2. Login to the Argo CD server using credentials from GitHub secrets
3. Add the repository that will be monitored by Argo CD
4. Use the Argo CD CLI to create a new application for the cluster, pointing to the repository path that contains the cluster manifests. This will make Argo CD deploy and sync the cluster.

So in summary, it enables GitOps workflow for provisioning and managing Kubernetes clusters using Argo CD, triggered by GitHub Actions.

Notice that you will need to fill in secrets in the GitHub Actions Secrets section as shown in the image below:

![GitHub Actions Secrets ](images/GitHub_Actions_Secrets.png)

These are the secrets:
- AKEYLESS_ACCESS_ID and AKEYLESS_API_ACCESS_KEY -> Credentials to access Akeyless to eventually drop the vCluster Kubeconfig in a static secret there.
- ARGOCD_USER -> admin
- ARGOCD_PASS -> the password you got from (kubectl get secret -n argocd argocd-initial-admin-secret -o json | jq -r '.data.password' | base64 --decode)
- ARGOCD_SERVER -> f1c6-24-150-170-114.ngrok-free.app (the ngrok server not URL, don't include https://)
ARGOCD_USER -> admin
- AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY -> AWS credentials to access the EKS cluster and generate vClusters
- CF_API_TOKEN and CF_ZONE_ID -> Credentials and Zone ID to access Cloudflare and create DNS records for the vClusters
- DOCKER_USERNAME and DOCKER_PASSWORD -> These are optional if you want to build your own Backstage image and push it to Docker Hub.
- GCP_CREDENTIALS -> Credentials to access GCP to eventually drop the vCluster Kubeconfig in a static secret in Akeyless.
- MYGITHUB_TOKEN -> you will need to create a Classic GitHub token from developer settings as shown in the next two images, or use the same one you have for Backstage in the `backstage/my-backstage-app/secrets.sh` file.
- TARGET_DOMAIN -> this is the hostname of the LoadBalancer that Traefik's ingressRouteTCP creates to access the vClusters. In case of EKS it's a hostname and in case of GKE it's an IP. (You will fill this out later after you create the EKS cluster.)

![Developer Settings](images/GitHub_Token_Settings.png)
![Token Scopes](images/GitHub_Token_Scopes.png)

### Common Issues and Troubleshooting

#### Issue 1: Repository Already Exists Error
**Error:** `Failed to create the User repository, Repository creation failed.: name already exists on this account`

**Solution:** 
- The Backstage template creates a **new** GitHub repository for each cluster deployment
- You must use a **unique repository name** that doesn't already exist
- Example: Instead of `vcluster-backstage-crossplane-demo`, use `vcluster-backstage-crossplane-demo-2` or `eks-cluster-<unique-name>`
- The template workflow: Creates new repo → Triggers GitHub Action → ArgoCD deploys

#### Issue 2: Branch Name Error (master vs main)
**Error:** `HttpError: No ref found for: master`

**Solution:**
- Ensure your repository uses `main` as the default branch (not `master`)
- Update the template file `backstage/my-backstage-app/packages/backend/templates/eks-cluster-crossplane/template.yaml`
- Change `branchOrTagName: 'master'` to `branchOrTagName: 'main'`
- Restart Backstage: `kubectl rollout restart deployment/backstage -n backstage`

#### Issue 3: ArgoCD Login Failures in GitHub Actions
**Error:** `Failed to login to ArgoCD` or `No ref found`

**Solutions:**
1. **Verify ngrok tunnel is running:**
   ```bash
   # Check if ngrok is running
   curl -s http://localhost:4040/api/tunnels
   
   # If not running, start it:
   kubectl port-forward -n argocd service/argocd-server 8080:443 &
   ngrok http https://localhost:8080 &
   ```

2. **Verify GitHub secrets are set correctly:**
   - `ARGOCD_SERVER`: Use only the hostname (e.g., `a7eb-24-150-170-114.ngrok-free.app`), **NOT** the full URL
   - `ARGOCD_USER`: `admin`
   - `ARGOCD_PASS`: Get it with:
     ```bash
     kubectl get secret -n argocd argocd-initial-admin-secret -o json | jq -r '.data.password' | base64 --decode
     ```

3. **Check ArgoCD server accessibility:**
   - The ngrok URL must be accessible from the internet
   - Test it: `curl https://your-ngrok-hostname.ngrok-free.app` (should return ArgoCD response)

#### Issue 4: Limited Kubernetes Versions in Backstage Template
**Issue:** Only seeing versions 1.28 and 1.29 in the dropdown

**Solution:**
- The template has been updated to include versions 1.28 through 1.34
- If you don't see newer versions, restart Backstage:
  ```bash
  kubectl rollout restart deployment/backstage -n backstage
  kubectl rollout status deployment/backstage -n backstage
  ```

#### Issue 5: GitHub Actions Workflow Improvements
The workflow now includes:
- Better error handling and validation
- Connectivity checks before login attempts
- Clearer error messages for troubleshooting
- Automatic secret validation

## Crossplane Secrets for Clouds

Most of the crossplane configuration in this repo were taken from Viktor Farcic, so shout out to him. Here is his original repo: https://github.com/vfarcic/crossplane-kubernetes

### AWS

#### Step 1: Prepare Your Credentials

Make sure you're in the `crossplane` folder.

You'll need your AWS Access Key ID and Secret Access Key. If you're using TeKanAid Premium, you can get these from the lesson on setting up AWS.

These should be formatted as follows in a file called `aws_credentials.conf` I have an example file for you called `aws_credentials-example.conf`:

```ini
[default]
aws_access_key_id = YOUR_ACCESS_KEY_ID
aws_secret_access_key = YOUR_SECRET_ACCESS_KEY
```

Replace `YOUR_ACCESS_KEY_ID` and `YOUR_SECRET_ACCESS_KEY` with your actual AWS credentials and rename the file to `aws_credentials.conf`. If you are a TeKanAid Premium subscriber, you can get these credentials from the TeKanAid lesson for setting up AWS.


### Step 2: Create the Secret in Kubernetes

You can create the Kubernetes secret from the `credentials.conf` file using `kubectl`. 

Run the following command:

```sh
kubectl create secret generic aws-creds --from-file=creds=/Users/saadullah/Documents/learning/vcluster-demos/crossplane/aws_credentials.conf -n crossplane-system
```


This command does the following:
- `create secret generic aws-creds` tells Kubernetes to create a new generic secret named `aws-creds`.
- `--from-file=creds=./credentials.conf` adds the content of your `credentials.conf` file to the secret under the key `creds`.
- `-n crossplane-system` specifies the namespace `crossplane-system` for the secret.

### Step 3: Verify the Secret

After creating the secret, you can verify it's correctly created in the `crossplane-system` namespace by running:

```sh
kubectl get secret aws-creds -n crossplane-system -o yaml
```

This command shows the details of the `aws-creds` secret. For security reasons, the actual credentials content will be base64 encoded.

### GCP

From the root of the repo run the following. Make sure you have your `google-creds.json` file present at `backstage/my-backstage-app/packages/backend/google-creds.json`
```bash
kubectl --namespace crossplane-system \
    create secret generic gcp-creds \
    --from-file creds=./backstage/my-backstage-app/packages/backend/google-creds.json
```

Now create the ProviderConfig after replacing the `<PROJECT_ID>` with your own project ID.

```bash
export PROJECT_ID=<PROJECT_ID>
echo "apiVersion: gcp.upbound.io/v1beta1
kind: ProviderConfig
metadata:
  name: default
spec:
  projectID: $PROJECT_ID
  credentials:
    source: Secret
    secretRef:
      namespace: crossplane-system
      name: gcp-creds
      key: creds" \
    | kubectl apply --filename -
```

## Create K8s Clusters with Crossplane

### EKS

#### Create the Cluster

You could create an EKS cluster directly as shown below or use backstage template to to do that which will use ArgoCD. The backstage template is explained later on.

```bash
kubectl create namespace infra
kubectl --namespace infra apply --filename ./crossplane/eks_claim.yaml
kubectl --namespace infra get clusterclaims
kubectl get managed
```

#### Access the Cluster

```bash
kubectl get secret a-team-eks-cluster -o jsonpath='{.data.kubeconfig}' | base64 -d > eks-kubeconfig.yaml
export KUBECONFIG=$(pwd)/eks-kubeconfig.yaml
kubectl get nodes
kubectl get namespaces
```

### GCP

#### Create the Cluster

You could create an GKE cluster directly as shown below or use backstage template to to do that which will use ArgoCD. The backstage template is explained later on.

```bash
kubectl create namespace infra
kubectl --namespace infra apply --filename ./crossplane/gke_claim.yaml
kubectl --namespace infra get clusterclaims
kubectl get managed
```

To get the kubeconfig:

```bash
gcloud container clusters get-credentials samgke --region us-east1 --project crossplaneprojects
```

## Delete the K8s Cluster with Crossplane

```bash
kubectl --namespace infra delete \
    --filename ./crossplane/eks_claim.yaml
kubectl --namespace infra delete \
    --filename ./crossplane/gke_claim.yaml
kubectl get managed

# Wait until all the resources are deleted (ignore `object` and
#   `release` resources)
```

## Backstage

### Backstage Installation

To install Backstage first make sure you're in the `backstage` folder then do the following:

1. Rename `secrets-example.sh` to `secrets.sh` file in the `backstage/my-backstage-app` folder and add the environment variables you want. This file won't be checked into git. The `GITHUB_TOKEN` can be the same one you created earlier.
2. Run the script `create_k8s_secrets_for_backstage.sh` which will create a file called: `my-backstage-secrets.yaml` like this:
```bash
/workspaces/platform-engineering-playground/backstage/my-backstage-app/create_k8s_secrets_for_backstage.sh
```
3. Create this secret with:
```bash
kubectl apply -f /Users/saadullah/Documents/learning/vcluster-demos/backstage/my-backstage-app/my-backstage-secrets.yaml
```
4. If you want to access GCP, put your google creds json file here: `backstage/my-backstage-app/packages/backend/google-creds.json` then create a secret like this:
```bash
kubectl create secret generic google-creds \
  --from-file=google-creds.json=/workspaces/platform-engineering-playground/backstage/my-backstage-app/packages/backend/google-creds.json \
  --namespace backstage
```
in the `backstage/my-backstage-app/values.yaml` file uncomment the following lines:
```yaml
  extraVolumeMounts:
    # - name: google-creds-volume
    #   mountPath: "/etc/secrets"
    #   readOnly: true

  extraVolumes:
    # - name: google-creds-volume
    #   secret:
    #     secretName: google-creds
```
5. Finally run the `helm` command to install Backstage:
```bash
helm upgrade --install backstage backstage/backstage --namespace backstage -f /Users/saadullah/Documents/learning/vcluster-demos/backstage/my-backstage-app/values.yaml --set backstage.image.tag=v0.0.2
```

Wait until both the backstage and postgresql pods are running:

```bash
watch kubectl get po -n backstage
```

### Backstage Access

To access Backstage, you can port-forward the service like this below (Make sure the pod is running for a minute or so first):
```bash
kubectl port-forward -n backstage service/backstage 7007:7007
```

### Backstage Templates

You will already have some built-in templates that were created with the backstage app that you can explore in the UI and also take a look at the template files in the `backstage/my-backstage-app/packages/backend/templates` directory.

#### Update Templates as Needed

**Required Template Updates:**

1. **Update Repository URL:**
   You will need to check the templates and make the necessary updates to work with your forked repo, specifically the 
   `repoUrl: 'github.com?repo=platform-engineering-playground&owner=TeKanAid-Subscription'`
   
   Update to your repository:
   ```yaml
   repoUrl: 'github.com?repo=vCluster-Backstage-ArgoCD-Pipeline&owner=saad946'
   ```

2. **Update Branch Name:**
   Ensure templates use `main` instead of `master`:
   ```yaml
   branchOrTagName: 'main'  # Not 'master'
   ```

3. **Update Kubernetes Versions:**
   The EKS cluster template now supports versions 1.28 through 1.34. If you need to update:
   ```yaml
   version:
     title: K8s Version
     type: string
     description: The K8s version to deploy
     enum:
       - "1.28"
       - "1.29"
       - "1.30"
       - "1.31"
       - "1.32"
       - "1.33"
       - "1.34"
   ```

4. **Template Files to Update:**
   - `backstage/my-backstage-app/packages/backend/templates/eks-cluster-crossplane/template.yaml`
   - `backstage/my-backstage-app/packages/backend/templates/generic-k8s-cluster/template.yaml`
   - `backstage/my-backstage-app/packages/backend/templates/vcluster/template.yaml`

**After Making Changes:**
```bash
# Commit and push changes
git add backstage/my-backstage-app/packages/backend/templates/
git commit -m "Update templates for new repository"
git push

# Restart Backstage to pick up template changes
kubectl rollout restart deployment/backstage -n backstage
kubectl rollout status deployment/backstage -n backstage
```

#### Register a New Template

But let's register a new one directly from the UI.

Click the `Create` button in the left naviation pane and then click the button called: `REGISTER EXISTING COMPONENT`

Enter the URL below where our K8s-Cluster-Crossplane template exists:
```
https://github.com/TeKanAid-Subscription/platform-engineering-playground/blob/main/backstage/my-backstage-app/packages/backend/templates/generic-k8s-cluster/template.yaml
```

Then once you've registered this template, you can now access it by clicking the `Create` button on the left navigation pane and selecting that template.

You can now create a K8s cluster with crossplane using Backstage. Here is the workflow:

Backstage -> GitHub Actions -> ArgoCD -> Crossplane -> you will end up with a secret in the newly created namespace in your cluster with the kubeconfig for the EKS cluster. 

You can check the progress of the K8s cluster creation by running the following commands:
```bash
kubens <your-cluster-name>
kubectl get managed
```

**Accessing the EKS Cluster:**

The secret name follows the pattern: `<cluster-name>-cluster` (not just `<cluster-name>`).

For example, if your cluster name is `vcluster-backstage-crossplane-demo`, the secret will be:
- Secret name: `vcluster-backstage-crossplane-demo-cluster`
- Namespace: `vcluster-backstage-crossplane-demo` (same as cluster name)

**Step 1: Find the secret:**
```bash
# List all secrets with cluster in the name
kubectl get secrets -A | grep cluster

# Or check in the cluster's namespace
kubectl get secrets -n <cluster-name> | grep cluster
```

**Step 2: Extract kubeconfig:**
```bash
# Get the kubeconfig (replace <cluster-name> with your actual cluster name)
kubectl get secret <cluster-name>-cluster -n <cluster-name> -o jsonpath='{.data.kubeconfig}' | base64 -d > eks-kubeconfig.yaml

# Example:
kubectl get secret vcluster-backstage-crossplane-demo-cluster -n vcluster-backstage-crossplane-demo -o jsonpath='{.data.kubeconfig}' | base64 -d > eks-kubeconfig.yaml
```

**Step 3: Use the kubeconfig:**
```bash
export KUBECONFIG=$(pwd)/eks-kubeconfig.yaml
kubectl get nodes
kubectl get namespaces
kubectl cluster-info
```

**Note:** If the kubeconfig from Crossplane doesn't have proper permissions, update it using AWS CLI:
```bash
# Update with AWS credentials for better permissions
aws eks update-kubeconfig --name <cluster-name> --region <region> --kubeconfig eks-kubeconfig-aws.yaml
export KUBECONFIG=$(pwd)/eks-kubeconfig-aws.yaml
```

In the case of a GKE cluster you can access the cluster using the following

To get the kubeconfig:

```bash
gcloud container clusters get-credentials samgke --region us-east1 --project crossplaneprojects
```

#### Register the New Cluster in ArgoCD

**Important:** Before registering, ensure you're logged into ArgoCD:
```bash
# Login to ArgoCD (replace with your ngrok URL if using tunnel)
argocd login adelaide-unerupted-nonimpulsively.ngrok-free.dev \
  --username admin \
  --password $(kubectl get secret -n argocd argocd-initial-admin-secret -o json | jq -r '.data.password' | base64 --decode) \
  --grpc-web \
  --insecure
```

**Method 1: Using AWS CLI (Recommended for EKS)**

If you have AWS CLI configured, this method ensures proper authentication:

```bash
# Step 1: Update kubeconfig with AWS credentials
aws eks update-kubeconfig --name <your-cluster-name> --region <region> --kubeconfig eks-kubeconfig-aws.yaml

# Step 2: Get the context name
export KUBECONFIG=$(pwd)/eks-kubeconfig-aws.yaml
kubectl config current-context

# Step 3: Add cluster to ArgoCD (use the context name from step 2)
argocd cluster add <context-name> \
  --name <cluster-name-in-argocd> \
  --kubeconfig $(pwd)/eks-kubeconfig-aws.yaml \
  --grpc-web \
  --insecure
```

**Example:**
```bash
# Update kubeconfig
aws eks update-kubeconfig --name vcluster-backstage-crossplane-demo --region us-east-1 --kubeconfig eks-kubeconfig-aws.yaml

# Get context (will be something like: arn:aws:eks:us-east-1:ACCOUNT:cluster/CLUSTER-NAME)
export KUBECONFIG=$(pwd)/eks-kubeconfig-aws.yaml
CONTEXT=$(kubectl config current-context)

# Register in ArgoCD
argocd cluster add $CONTEXT --name eks-dev --kubeconfig $(pwd)/eks-kubeconfig-aws.yaml --grpc-web --insecure
```

**Method 2: Using Existing Kubeconfig (May Require Permissions)**

If you already have a kubeconfig from Crossplane:

```bash
# Extract kubeconfig from secret
kubectl get secret <cluster-name>-cluster -n <cluster-name> -o jsonpath='{.data.kubeconfig}' | base64 -d > eks-kubeconfig.yaml

# Set context
export KUBECONFIG=$(pwd)/eks-kubeconfig.yaml
kubectl config current-context

# Add to ArgoCD
argocd cluster add <context-name> --name <cluster-name-in-argocd> --kubeconfig $(pwd)/eks-kubeconfig.yaml --grpc-web --insecure
```

**Note:** If you get "Unauthorized" errors with Method 2, use Method 1 (AWS CLI) which ensures proper IAM permissions.

**Verify Cluster Registration:**
```bash
argocd cluster list --grpc-web --insecure
```

You should see your cluster listed. The status may show "Unknown" until applications are deployed to it.

**Troubleshooting Cluster Registration:**

- **Error: "Unauthorized" or "failed to create service account"**
  - Use AWS CLI method (Method 1) instead
  - Ensure your AWS credentials have proper EKS permissions
  - The kubeconfig from Crossplane may not have sufficient RBAC permissions

- **Error: "ArgoCD CLI not found"**
  ```bash
  # Install ArgoCD CLI (macOS)
  brew install argocd
  
  # Or download directly
  curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-darwin-arm64
  chmod +x /usr/local/bin/argocd
  ```

- **Error: "Connection refused" or "Cannot reach ArgoCD"**
  - Ensure ArgoCD is running: `kubectl get pods -n argocd`
  - If using ngrok, ensure tunnel is active: `curl http://localhost:4040/api/tunnels`
  - Check port-forward is running: `kubectl port-forward -n argocd service/argocd-server 8080:443`

## Create vClusters for Devs on our EKS Cluster

### Add the Target Domain

As platform engineers, we need to add the Target Domain to GitHub Actions secrets. The Target Domain is the hostname of the LoadBalancer that Traefik's ingressRouteTCP creates to access the vClusters in the case of EKS. In the case of GKE, it will be an IP address.

To get the value, run the following command:

```bash
# For EKS
kubectl get svc traefik -n traefik -o=jsonpath='{.status.loadBalancer.ingress[0].hostname}'
# For GKE
kubectl get svc traefik -n traefik -o=jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Now add this value to the `TARGET_DOMAIN` GitHub Actions secret.

### Add Parameter Values to the Backstage vCluster Template

As platform engineers, we need to add some values to variables in the Backstage vCluster template.

 add the endpoint for our K8s cluster inside our new vCluster template in Backstage.

These are the parameters that you will need to update based on your situation.

- hostEKSClusterName
- hostEKS_URLforArgo
- hostGKEClusterName
- hostGKEprojectName
- hostGKE_URLforArgo
- hostAKSClusterName
- hostAKS_URLforArgo

They are straight forward. Just note that the `hostEKS_URLforArgo`, `hostGKE_URLforArgo`, and `hostAKS_URLforArgo` parameters are the endpoints for our host K8s clusters. You can get the value of the endpoints from ArgoCD under settings > clusters and get the server URL under General.

Also remember to update  the appropriate parameters for your GitHub actions workflow name, the repo and branch name.

Here is an example:

```yaml
    - id: github-action
      name: Trigger GitHub Action
      action: github:actions:dispatch
      input:
        workflowId: vcluster_deploy.yaml
        repoUrl: 'github.com?repo=vcluster-demos&owner=tekanaid' # update this
        branchOrTagName: 'master' # update this
        workflowInputs:
          clusterName: ${{ parameters.clusterName }}
          repoURLforArgo: ${{ steps['publish'].output.remoteUrl }}
          hostClusterType: ${{ parameters.hostClusterType | string}}
          # You will need to make updates to all the parameters below.
          hostEKSClusterName: eks-host-cluster
          hostEKS_URLforArgo: https://5D795F1CE2F22C3B3BB93E19AA666DF4.gr7.us-east-1.eks.amazonaws.com
          hostGKEClusterName: samgke
          hostGKEprojectName: crossplaneprojects
          hostGKE_URLforArgo: https://34.23.68.174
          hostAKSClusterName: aks-host-cluster
          hostAKS_URLforArgo: https://
```

### Register a New vCluster Template in Backstage

Let's register a new template for creating a vCluster in Backstage.

Click the `Create` button in the left naviation pane and then click the button called: `REGISTER EXISTING COMPONENT`

Enter the URL below where our EKS-Cluster-Crossplane template exists:
```
https://github.com/TeKanAid-Subscription/platform-engineering-playground/blob/main/backstage/my-backstage-app/packages/backend/templates/vcluster/template.yaml
```

Then once you've registered this template, you can now access it by clicking the `Create` button on the left navigation pane and selecting that template.

You can now create a vCluster using Backstage, just follow the template steps and input values in the forms.

### Access the New vCluster

Wait until the vCluster component dashboard in Backstage shows the new vCluster as ready. 

![ArgoCD Output in Backstage](images/ArgoCD_output_in_Backstage.png)

Then, you can access the vCluster in Akeyless by getting the kubeconfig from the `Kubeconfig` static secret.

Get the Akeyless static secret at `/vclusters/Kubeconfig`. This is the base64 encoding of the kubeconfig file. Run the commands below to decode and use the kubeconfig:

```bash
ENCODED_KUBECONFIG=YXBpVmVyc2lvbjogdjEKY2x1c3RlcnM6Ci0gY2x1c3RlcjoKICAgIGNlcnRpZmljYXRlLWF1dGhvcml0eS1kYXRhOiBMUzB0TFMxQ1JVZEpUaUJEUlZKVVNVWkpRMEZVUlMwdExTMHRDazFKU1VKa2VrTkRRVkl5WjBGM1NVSkJaMGxDUVVSQlMwSm5aM0ZvYTJwUFVGRlJSRUZxUVdwTlUwVjNTSGRaUkZaUlVVUkVRbWh5VFROTmRHTXlWbmtLWkcxV2VVeFhUbWhSUkVVelRWUk5lVTFVU1hwUFJFVjNTR2hqVGsxcVVYZE9SRVV4VFdwQmVFOVVVWGhYYUdOT1RYcFJkMDVFUlhwTmFrRjRUMVJSZUFwWGFrRnFUVk5GZDBoM1dVUldVVkZFUkVKb2NrMHpUWFJqTWxaNVpHMVdlVXhYVG1oUlJFVXpUVlJOZVUxVVNYcFBSRVYzVjFSQlZFSm5ZM0ZvYTJwUENsQlJTVUpDWjJkeGFHdHFUMUJSVFVKQ2QwNURRVUZSUW1nd05VMVlTSE5PYm1salpUZzViVFZRWnk5MU4wTXJSMDQyYnpOcmNtVnhiRGQ2V1ZSRlQxY0tVbGh6Vm1wcVVGUmpRVzVTU2tGMGN6Sk5helZQY0VsR1YxQk9hbGwzUW1WMVlURTRURkl4VkV0WGFVVnZNRWwzVVVSQlQwSm5UbFpJVVRoQ1FXWTRSUXBDUVUxRFFYRlJkMFIzV1VSV1VqQlVRVkZJTDBKQlZYZEJkMFZDTDNwQlpFSm5UbFpJVVRSRlJtZFJWVFpUU1ZSbmJrSmtURFZDTm05ME5YY3daMnQ0Q2xCMmVGSlBjVEIzUTJkWlNVdHZXa2w2YWpCRlFYZEpSRk5CUVhkU1VVbG5WVVJYYTNWMFNWQlBWMk54TTNSbVdXazBNVGt4TDFoSmFYRk9RV2gyWm1zS1NWRXJSUzlRV1VoNFVuTkRTVkZETjNodWRrSklZalYzVkdjeldFZFFkelU1VkM5RVRIRndTelJtVjJWaWFWYzFPREZrWjFaRWJHMTBkejA5Q2kwdExTMHRSVTVFSUVORlVsUkpSa2xEUVZSRkxTMHRMUzBLCiAgICBzZXJ2ZXI6IGh0dHBzOi8vc2FtLWVrcy12Y2x1c3Rlci50ZWthbmFpZC5jb20KICBuYW1lOiBteS12Y2x1c3Rlcgpjb250ZXh0czoKLSBjb250ZXh0OgogICAgY2x1c3RlcjogbXktdmNsdXN0ZXIKICAgIHVzZXI6IG15LXZjbHVzdGVyCiAgbmFtZTogbXktdmNsdXN0ZXIKY3VycmVudC1jb250ZXh0OiBteS12Y2x1c3RlcgpraW5kOiBDb25maWcKcHJlZmVyZW5jZXM6IHt9CnVzZXJzOgotIG5hbWU6IG15LXZjbHVzdGVyCiAgdXNlcjoKICAgIGNsaWVudC1jZXJ0aWZpY2F0ZS1kYXRhOiBMUzB0TFMxQ1JVZEpUaUJEUlZKVVNVWkpRMEZVUlMwdExTMHRDazFKU1VKclJFTkRRVlJsWjBGM1NVSkJaMGxKVUdsWU5VOVpTSGx2VERSM1EyZFpTVXR2V2tsNmFqQkZRWGRKZDBsNlJXaE5RamhIUVRGVlJVRjNkMWtLWVhwT2VreFhUbk5oVjFaMVpFTXhhbGxWUVhoT2VrVjZUV3BGZVUxNlozaE5RalJZUkZSSk1FMUVVWGhPVkVsM1RWUnJNRTFXYjFoRVZFa3hUVVJSZUFwT1ZFbDNUVlJyTUUxV2IzZE5SRVZZVFVKVlIwRXhWVVZEYUUxUFl6TnNlbVJIVm5SUGJURm9Zek5TYkdOdVRYaEdWRUZVUW1kT1ZrSkJUVlJFU0U0MUNtTXpVbXhpVkhCb1drY3hjR0pxUWxwTlFrMUhRbmx4UjFOTk5EbEJaMFZIUTBOeFIxTk5ORGxCZDBWSVFUQkpRVUpLUWk5V2MyMUJPVmRHTlV0U1VrMEtZMkpHVGtGWU9ETnNiMXBQYXpaU1JXSkdMMGxqVXpWVmRIbEJMM00xU2pRMlUzTjRlRFpPWTBack9VVTJUMUE1U1M4MldFWkNlSFJqYXk5M1JtbERlQXBOT0ZOTloyRXlhbE5FUWtkTlFUUkhRVEZWWkVSM1JVSXZkMUZGUVhkSlJtOUVRVlJDWjA1V1NGTlZSVVJFUVV0Q1oyZHlRbWRGUmtKUlkwUkJha0ZtQ2tKblRsWklVMDFGUjBSQlYyZENVVWRGSzA5T09HUjJia2RYVldOYVprVk5NVUp1YW14NWNtUlpSRUZMUW1kbmNXaHJhazlRVVZGRVFXZE9TRUZFUWtVS1FXbEJXalpDTTJ0R2J6SldXVWRWU1c5SU9DODRibEpWVWpCSVVHcDVaVWhJZEhacWNqQnhNVk5FVjIwNWQwbG5TMEZVZG1KNWIzRXdiR1kxWVVSMGJBcDNhRXN6VDFONVFVMXFOMFpSTlVOVE9YRmlZbEJXWW5oallVazlDaTB0TFMwdFJVNUVJRU5GVWxSSlJrbERRVlJGTFMwdExTMEtMUzB0TFMxQ1JVZEpUaUJEUlZKVVNVWkpRMEZVUlMwdExTMHRDazFKU1VKbFJFTkRRVkl5WjBGM1NVSkJaMGxDUVVSQlMwSm5aM0ZvYTJwUFVGRlJSRUZxUVdwTlUwVjNTSGRaUkZaUlVVUkVRbWh5VFROTmRGa3llSEFLV2xjMU1FeFhUbWhSUkVVelRWUk5lVTFVU1hwUFJFVjNTR2hqVGsxcVVYZE9SRVV4VFdwQmVFOVVVWGhYYUdOT1RYcFJkMDVFUlhwTmFrRjRUMVJSZUFwWGFrRnFUVk5GZDBoM1dVUldVVkZFUkVKb2NrMHpUWFJaTW5od1dsYzFNRXhYVG1oUlJFVXpUVlJOZVUxVVNYcFBSRVYzVjFSQlZFSm5ZM0ZvYTJwUENsQlJTVUpDWjJkeGFHdHFUMUJSVFVKQ2QwNURRVUZVYm5wMFJUZGplV1YyVkRFMFJVYzJSbVJyU0RaVFpuWmxWRWRrTVdGQ2FtWjJjVzE1ZVVsSGVFa0tkVTl3ZEdZclREZGFiblJ5VkhnMVdHSTNZazl0TUVkT1IyVkVTa3RoTVc5MU5XeFBWM2hEYkVGaE1XeHZNRWwzVVVSQlQwSm5UbFpJVVRoQ1FXWTRSUXBDUVUxRFFYRlJkMFIzV1VSV1VqQlVRVkZJTDBKQlZYZEJkMFZDTDNwQlpFSm5UbFpJVVRSRlJtZFJWVUpvVUdwcVpraGlOWGhzYkVoSFdIaEVUbEZhQ2pRMVkzRXpWMEYzUTJkWlNVdHZXa2w2YWpCRlFYZEpSRk5SUVhkU1owbG9RVXBSYlVkblVreEtVbEJyV0dJNVNXZDVWMU5DT1VWUVl6bE5WblJ2UXpVS2JIUlZaMDVCY1VnelUxaGxRV2xGUVhVd2FtMTFWVkl4ZWpseGFGTnFiVTh3TldOa05WQXpRWFpRVXpKRFQxUlZMelJaTmxkblUyUjNNVlU5Q2kwdExTMHRSVTVFSUVORlVsUkpSa2xEUVZSRkxTMHRMUzBLCiAgICBjbGllbnQta2V5LWRhdGE6IExTMHRMUzFDUlVkSlRpQkZReUJRVWtsV1FWUkZJRXRGV1MwdExTMHRDazFJWTBOQlVVVkZTVUp4WW5sTGJHOUZXREZuVGtONFVscFZOekpRY3pWV1oyNUZjMmRJVURWTk5XTnFjVWxaUTI5VlRFeHZRVzlIUTBOeFIxTk5ORGtLUVhkRlNHOVZVVVJSWjBGRmEwZzVWM2xaUkRGWldHdHdSa1Y0ZUhOVk1FSm1lbVZYYUdzMlZIQkZVbk5ZT0doNFRHeFRNMGxFSzNwcmJtcHdTM3BJU0Fwdk1YZFhWREJVYnpRdk1Hb3ZjR05WU0VjeGVWUXZRVmRKVEVWNmVFbDVRbkpSUFQwS0xTMHRMUzFGVGtRZ1JVTWdVRkpKVmtGVVJTQkxSVmt0TFMwdExRbz0K
echo $ENCODED_KUBECONFIG | base64 --decode > vcluster_kubeconfig.yaml
export KUBECONFIG=vcluster_kubeconfig.yaml
kubectl get ns
kubectl get nodes
```

#### Congrats on building an Internal Developer Platform with vCluster!

## Quick Reference Guide

### Essential Commands

**ArgoCD Setup:**
```bash
# Get admin password
kubectl get secret -n argocd argocd-initial-admin-secret -o json | jq -r '.data.password' | base64 --decode

# Port-forward ArgoCD
kubectl port-forward -n argocd service/argocd-server 8080:443

# Start ngrok tunnel (in background)
kubectl port-forward -n argocd service/argocd-server 8080:443 & \
ngrok http https://localhost:8080 & \
sleep 8 && curl -s http://localhost:4040/api/tunnels | grep -o 'https://[a-z0-9-]*\.ngrok[^"]*' | head -1

# Login to ArgoCD CLI
argocd login <ngrok-hostname> --username admin --password <password> --grpc-web --insecure
```

**EKS Cluster Access:**
```bash
# Extract kubeconfig
kubectl get secret <cluster-name>-cluster -n <cluster-name> -o jsonpath='{.data.kubeconfig}' | base64 -d > eks-kubeconfig.yaml

# Use kubeconfig
export KUBECONFIG=$(pwd)/eks-kubeconfig.yaml
kubectl get nodes
```

**Register Cluster in ArgoCD:**
```bash
# Update kubeconfig with AWS credentials
aws eks update-kubeconfig --name <cluster-name> --region <region> --kubeconfig eks-kubeconfig-aws.yaml

# Add to ArgoCD
export KUBECONFIG=$(pwd)/eks-kubeconfig-aws.yaml
CONTEXT=$(kubectl config current-context)
argocd cluster add $CONTEXT --name <cluster-name-in-argocd> --kubeconfig $(pwd)/eks-kubeconfig-aws.yaml --grpc-web --insecure
```

**Backstage Management:**
```bash
# Port-forward Backstage
kubectl port-forward -n backstage service/backstage 7007:7007

# Restart Backstage (after template changes)
kubectl rollout restart deployment/backstage -n backstage
kubectl rollout status deployment/backstage -n backstage
```

### GitHub Actions Secrets Checklist

Ensure these secrets are set in your GitHub repository:

- [ ] `ARGOCD_SERVER` - ngrok hostname (without https://)
- [ ] `ARGOCD_USER` - admin
- [ ] `ARGOCD_PASS` - ArgoCD admin password
- [ ] `MYGITHUB_TOKEN` - GitHub personal access token
- [ ] `AWS_ACCESS_KEY_ID` - AWS access key
- [ ] `AWS_SECRET_ACCESS_KEY` - AWS secret key
- [ ] `TARGET_DOMAIN` - Traefik LoadBalancer hostname/IP (set after EKS cluster creation)

### Common Workflows

**Creating a New EKS Cluster via Backstage:**
1. Access Backstage UI (port-forward on 7007)
2. Click "Create" → Select "New EKS Cluster with Crossplane"
3. Fill in form:
   - **Repository Location:** Use a **unique** repository name (must not exist)
   - **Cluster Name:** Your desired cluster name
   - **Node Size:** small/medium/large
   - **K8s Version:** 1.28-1.34
   - **Min Node Count:** 1-3
4. Submit and wait for GitHub Action to complete
5. Check cluster status: `kubectl get managed -n <cluster-name>`
6. Extract kubeconfig and connect to cluster
7. Register cluster in ArgoCD

**Troubleshooting Workflow:**
1. Check Backstage logs: `kubectl logs -n backstage deployment/backstage`
2. Check GitHub Actions workflow runs
3. Verify ngrok tunnel: `curl http://localhost:4040/api/tunnels`
4. Check ArgoCD applications: `argocd app list --grpc-web --insecure`
5. Verify secrets exist: `kubectl get secrets -n <cluster-name>`

### Key Files and Locations

- **Templates:** `backstage/my-backstage-app/packages/backend/templates/`
- **GitHub Workflows:** `.github/workflows/`
- **Crossplane Configs:** `crossplane/`
- **Backstage Config:** `backstage/my-backstage-app/app-config.yaml`
