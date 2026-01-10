#!/bin/bash
set -e  # Exit on any error

mkdir -p logs

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No 

# Helper check functions
check_argocd_namespace() {
    echo "Checking argocd namespace exists..."
    sudo kubectl get ns argocd > /dev/null || { echo -e "${RED}FAIL: argocd namespace not found!${NC}"; exit 1; }
    echo -e "${GREEN}Argo CD namespace ready${NC}"
}

check_gitlab_namespace() {
    echo "Checking gitlab namespace exists..."
    sudo kubectl get ns gitlab > /dev/null || { echo -e "${RED}FAIL: gitlab namespace not found!${NC}"; exit 1; }
    echo -e "${GREEN}GitLab namespace ready${NC}"
}

check_gitlab_pods() {
    echo "Checking GitLab webservice pod is running..."
    sudo kubectl get pods -n gitlab | grep webservice > /dev/null || { echo -e "${RED}FAIL: GitLab webservice not running!${NC}"; exit 1; }
    echo -e "${GREEN}GitLab webservice running${NC}"
}

check_all_namespaces() {
    echo "Checking all required namespaces (argocd, dev, gitlab)..."
    sudo kubectl get ns | grep -E "argocd|dev|gitlab" | wc -l | grep -q 3 || { echo -e "${RED}FAIL: Missing required namespaces!${NC}"; exit 1; }
    echo -e "${GREEN}All namespaces present${NC}"
}

check_dev_pods() {
    echo "Checking playground app in dev namespace..."
    sudo kubectl get pods -n dev | grep playground > /dev/null || { echo -e "${RED}FAIL: Playground app not running!${NC}"; exit 1; }
    echo -e "${GREEN}Playground app running${NC}"
}

check_app_access() {
    echo "Checking app accessibility at http://localhost:8888..."
    curl -s http://localhost:8888/ | grep -E "v1|v2" > /dev/null || { echo -e "${RED}FAIL: App not responding!${NC}"; exit 1; }
    echo -e "${GREEN}Application accessible${NC}"
}

check_argocd_app_status() {
    echo "Checking Argo CD application sync and health status..."
    sudo argocd app get playground-app | grep -E "Synced|Healthy" > /dev/null || { echo -e "${RED}FAIL: Argo CD app not synced/healthy!${NC}"; exit 1; }
    echo -e "${GREEN}Argo CD application synced and healthy${NC}"
}

########### STEP 1: K3d CLUSTER CREATION ###########
echo ""
echo "STEP 1: Creating K3d cluster..."
echo "Creating cluster 'dbanfiC' with port 8080:80 exposed for load balancer"
chmod +x ./clusterCreate.sh
bash ./clusterCreate.sh

echo "Verifying cluster creation..."
sudo k3d cluster list
sudo kubectl get nodes
sleep 45 # Wait for system pods to initialize
echo "Checking system pods..."
sudo kubectl get pods -A


########### STEP 2: ArgoCD INSTALLATION ###########
echo ""
echo "STEP 2: Installing Argo CD..."
echo "Installing Argo CD in namespace 'argocd' and configuring credentials from .env"
chmod +x ./argocdInstall.sh
bash ./argocdInstall.sh

echo "Verifying Argo CD installation..."
sleep 5
check_argocd_namespace
sudo kubectl get pods -n argocd
echo


########### STEP 3: GITLAB DEPLOYMENT ###########
echo ""
echo "STEP 3: Deploying GitLab..."
echo "Installing GitLab via Helm with custom root password from .env"
echo "Creating namespace, root user, and configuring GitLab instance"
chmod +x ./deployGitlab.sh
bash ./deployGitlab.sh

echo "Verifying GitLab deployment..."
check_gitlab_namespace
check_gitlab_pods
echo

########### STEP 4: GITLAB REPOSITORY CREATION ###########
echo ""
echo "STEP 4: Creating GitLab repository and pushing manifests..."
echo "Generating GitLab access token and creating 'dbanfi_playground' project"
echo "Pushing application manifests to GitLab repository"
chmod +x ./createGitlabRepo.sh
bash ./createGitlabRepo.sh

########### STEP 5: DEPLOY APPLICATION VIA ArgoCD ###########
echo ""
echo "STEP 5: Deploying application via Argo CD..."
echo "Creating 'dev' namespace and configuring Argo CD application"
echo "Adding GitLab repository to Argo CD with access token"
echo "Syncing and deploying playground app from GitLab manifests"
chmod +x ./argocdDeploy.sh
bash ./argocdDeploy.sh

########### FINAL VERIFICATION ###########
echo ""
echo "=========================================="
echo "FINAL VERIFICATION:"
echo "=========================================="
check_all_namespaces
check_dev_pods
check_app_access
check_argocd_app_status

echo ""
echo "=========================================="
echo "SETUP COMPLETE!"
echo "=========================================="
echo ""
echo "Access URLs:"
echo "  • Application: http://localhost:8888/"
echo "  • Argo CD UI: https://localhost:8081/ (admin / from .env)"
echo "  • GitLab UI: http://localhost:8082/ (root / from .env)"
echo ""
echo "To toggle between app versions:"
echo "  ./togglePlaygroundVersion.sh"
echo ""
