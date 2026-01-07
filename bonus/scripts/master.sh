#!/bin/bash
set -e  # Exit on any error

mkdir -p logs

echo "========================================"
echo "Inception-of-Things (IoT) Bonus Master Setup"
echo "Version: 3.1 - January 2026"
echo "========================================"

# Helper check functions (split and embedded)
check_namespaces() {
    echo "Checking namespaces (argocd, dev, gitlab)..."
    kubectl get ns | grep -E "argocd|dev|gitlab" > /dev/null || { echo "FAIL: Missing required namespaces!"; exit 1; }
    echo "OK"
}

check_gitlab_pods() {
    echo "Checking GitLab pods (webservice running)..."
    kubectl get pods -n gitlab | grep webservice > /dev/null || { echo "FAIL: GitLab webservice not running!"; exit 1; }
    echo "OK"
}

check_dev_pods() {
    echo "Checking playground app in dev namespace..."
    kubectl get pods -n dev | grep playground > /dev/null || { echo "FAIL: Playground app not running!"; exit 1; }
    echo "OK"
}

check_app_access() {
    echo "Checking app accessibility (curl localhost:8888)..."
    curl -s http://localhost:8888/ | grep -E "v1|v2" > /dev/null || { echo "FAIL: App not responding! (Check k3d port mapping)"; exit 1; }
    echo "OK"
}

check_argocd_status() {
    echo "Checking Argo CD application status..."
    argocd app get playground-app | grep -E "Synced|Healthy" > /dev/null || { echo "FAIL: Argo CD app not synced/healthy!"; exit 1; }
    echo "OK"
}

show_gitlab_password() {
    echo "GitLab root password (for UI access):"
    kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -ojsonpath='{.data.password}' | base64 --decode
}

########### STEP 2: K3d CLUSTER CREATION ###########
# Create K3d cluster 
chmod +x ./clusterCreate.sh
bash ./clusterCreate.sh

sudo k3d cluster list #(should show dbanfiC running).
sudo kubectl get nodes #(should show one ready node).
sleep 45 # Wait a moment for system pods to start
sudo kubectl get pods -A #(system pods like Traefik should be running).


# Step 3: Reconfigure Argo CD
echo ""
echo "STEP 3: Reconfiguring Argo CD to use local GitLab..."

########### STEP 3: ArgoCD INSTALLATION ###########

# Install ArgoCD into the cluster
chmod +x ./argocdInstall.sh
bash ./argocdInstall.sh

# Verify installation
sleep 5
sudo kubectl get pods -n argocd #(all pods ready, e.g., argocd-server, argocd-application-controller).


# Step 1: Deploy GitLab
echo ""
echo "STEP 1: Deploying GitLab..."
chmod +x ./deployGitlab.sh
bash ./deployGitlab.sh

# Check after deployment
check_namespaces
check_gitlab_pods
echo "GitLab deployed successfully with root user configured."
echo

# Step 2: Create GitLab repository
echo ""
echo "STEP 2: Create GitLab repository"
echo "The script will prompt for your GitLab password..."
chmod +x ./createGitlabRepo.sh
bash ./createGitlabRepo.sh

########### STEP 4: DEPLOY APPLICATION VIA ArgoCD ###########
chmod +x ./argocdDeploy.sh
bash ./argocdDeploy.sh



# Final comprehensive checks
echo ""
echo "FINAL VERIFICATION:"
check_dev_pods
check_app_access
check_argocd_status
