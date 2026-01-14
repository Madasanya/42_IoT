
#!/bin/bash
set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p logs

# ========================================
# Inception-of-Things (IoT) P3 Master Setup
# ========================================
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# to activate the port forwarding again after script ends, run:
# sudo kubectl port-forward svc/argocd-server -n argocd 8081:443

# to view argocd UI, open a browser and go to:
# https://localhost:8081

# Note: The port-forward will be automatically cleaned up when the script exits due to the trap set earlier.

echo -e "${GREEN}========================================"
echo "Inception-of-Things (IoT) P3 Master Setup"
echo "========================================"${NC}


# -------- STEP 1: PREREQUISITES INSTALLATION --------
echo -e "\n${GREEN}STEP 1: Prerequisites Installation${NC}"
echo "Checking required tools..."
docker --version
k3d --version
kubectl version --client
argocd version --client

# -------- STEP 2: K3d CLUSTER CREATION --------
echo -e "\n${GREEN}STEP 2: K3d Cluster Creation${NC}"
echo "Creating K3d cluster..."
chmod +x ./clusterCreate.sh
bash ./clusterCreate.sh

echo "Verifying cluster creation..."
sudo k3d cluster list # should show dbanfiC running
sudo kubectl get nodes # should show one ready node
sleep 45 # Wait a moment for system pods to start
echo "Checking system pods..."
sudo kubectl get pods -A # system pods like Traefik should be running

# -------- STEP 3: ArgoCD INSTALLATION --------
echo -e "\n${GREEN}STEP 3: ArgoCD Installation${NC}"
echo "Installing ArgoCD into the cluster..."
chmod +x ./argocdInstall.sh
bash ./argocdInstall.sh

echo "Verifying ArgoCD installation..."
sleep 5
sudo kubectl get pods -n argocd # all pods ready, e.g., argocd-server, argocd-application-controller

# -------- STEP 4: DEPLOY APPLICATION VIA ArgoCD --------
echo -e "\n${GREEN}STEP 4: Deploy Application via ArgoCD${NC}"
chmod +x ./argocdDeploy.sh
bash ./argocdDeploy.sh

# -------- STEP 5: CLONE GITHUB REPOSITORY --------
echo -e "\n${GREEN}STEP 5: Clone GitHub Repository${NC}"
REPO_URL="https://github.com/mr-bammby/dbanfi_playground.git" # <-- Set your repo URL here
CLONE_DIR="/tmp/github-repo-dbanfi_playground"
if [ -d "$CLONE_DIR" ]; then
	echo "Removing existing repo at $CLONE_DIR..."
	rm -rf "$CLONE_DIR"
fi
echo "Cloning repository from $REPO_URL to $CLONE_DIR..."

git clone "$REPO_URL" "$CLONE_DIR"

# Fix permissions so non-root scripts can modify the repo
echo "Fixing permissions for $CLONE_DIR..."
chown -R "$SUDO_USER":"$SUDO_USER" "$CLONE_DIR"
chmod -R u+w "$CLONE_DIR"

cd "$SCRIPT_DIR" || exit 1

# -------- FINAL LINKS & INFO --------
echo -e "\n${GREEN}=========================================="
echo "SETUP COMPLETE!"
echo "=========================================="${NC}
echo ""
echo "Access URLs:"
echo "  • Application: http://localhost:8888/"
echo "  • Argo CD UI: https://localhost:8081/ (admin / see .env)"
echo ""
echo "To toggle between app versions:"
echo "  ./togglePlaygroundVersion.sh"
echo ""
