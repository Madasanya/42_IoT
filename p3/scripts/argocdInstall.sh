
# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color
#!/bin/bash

# Ensure cleanup of port-forward on script exit
cleanup() {
  echo -e "${YELLOW}Cleaning up port-forward...${NC}"
  sudo pkill -f "kubectl port-forward svc/argocd-server" 2>/dev/null
  curl -kLs "https://localhost:8081" 1>/dev/null 2>/dev/null
}
trap cleanup EXIT

# Create the Argo CD namespace and install:
echo -e "${YELLOW}Creating ArgoCD namespace and installing...${NC}"
sudo kubectl create namespace argocd
sudo kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for pods to start
echo -e "${YELLOW}Waiting for ArgoCD pods to be ready...${NC}"
sudo kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

# Get the initial admin password from the secret
INITIAL_ARGOCD_PASSWORD=$(sudo kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo -e "${YELLOW}Initial ArgoCD password retrieved from secret${NC}"

# Forward the port in the background and suppress all output
nohup  $PWD/portForward.sh argocd argocd-server 8081:443 >  $PWD/logs/argocd-portforward.log 2>&1 &
PORT_FORWARD_PID=$!

# Wait for port forwarding to be ready
sleep 5

# Login to ArgoCD using the initial password
sudo argocd login localhost:8081 --insecure --username admin --password "$INITIAL_ARGOCD_PASSWORD"

# Source .env file for new password
if [ -f "$PWD/.env" ]; then
  source "$PWD/.env"
else
  echo -e "${RED}.env file not found in $PWD. Please create it with ARGOCD_PASSWORD variable.${NC}"
  exit 1
fi

# Validate sourced password
if [ -z "$ARGOCD_PASSWORD" ]; then
  echo -e "${RED}ARGOCD_PASSWORD not set in .env file.${NC}"
  exit 1
fi

sudo argocd account update-password --current-password "$INITIAL_ARGOCD_PASSWORD" --new-password "$ARGOCD_PASSWORD"

echo -e "${YELLOW}Changing ArgoCD password to the one specified in .env file...${NC}"
sudo argocd account update-password --current-password "$INITIAL_ARGOCD_PASSWORD" --new-password "$ARGOCD_PASSWORD"
echo -e "${GREEN}ArgoCD password changed successfully${NC}"

