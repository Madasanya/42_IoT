#!/bin/bash
set -e

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Load credentials from .env file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
  source "$SCRIPT_DIR/.env"
else
  echo -e "${RED}Error: .env file not found in $SCRIPT_DIR${NC}"
  exit 1
fi

# Create the dev namespace where the application will be deployed
sudo kubectl create namespace dev 2>/dev/null || echo -e "${YELLOW}Namespace 'dev' already exists${NC}"

# Login to ArgoCD
echo -e "${YELLOW}Logging into ArgoCD...${NC}"
LOGIN_OUTPUT=$(sudo argocd login localhost:8081 --insecure --username admin --password "$ARGOCD_PASSWORD" 2>&1)
LOGIN_EXIT=$?

if [ $LOGIN_EXIT -ne 0 ]; then
  echo -e "${RED}ArgoCD login failed${NC}"
  exit 1
fi

echo -e "${GREEN}Successfully logged into ArgoCD${NC}"

# Generate GitLab access token for ArgoCD
echo -e "${YELLOW}Generating GitLab access token for ArgoCD...${NC}"
TOOLBOX_POD=$(sudo kubectl get pod -n gitlab -l app=toolbox -o jsonpath='{.items[0].metadata.name}')

GITLAB_TOKEN=$(sudo kubectl exec -n gitlab "$TOOLBOX_POD" -- gitlab-rails runner "$(cat $PWD/create_gitlab_token.rb)" argocd-token read_repository,write_repository 2>&1 | grep -E '^glpat-')

if [ -z "$GITLAB_TOKEN" ] || ! echo "$GITLAB_TOKEN" | grep -q "^glpat-"; then
  echo -e "${RED}Failed to generate GitLab access token${NC}"
  exit 1
fi

echo -e "${GREEN}GitLab access token generated${NC}"

# Add GitLab repository to ArgoCD with credentials
echo -e "${YELLOW}Adding GitLab repository to ArgoCD...${NC}"
sudo argocd repo add http://gitlab-webservice-default.gitlab.svc:8181/root/dbanfi_playground.git \
  --username root \
  --password "$GITLAB_TOKEN" \
  --insecure-skip-server-verification

if [ $? -ne 0 ]; then
  echo -e "${YELLOW}Repository add command returned an error, but it may already be added${NC}"
else
  echo -e "${GREEN}Repository added to ArgoCD${NC}"
fi

# Create the ArgoCD application from the configuration file
echo -e "${YELLOW}Create ArgoCD application for playground app...${NC}"
sudo kubectl apply -f $PWD/../confs/application.yaml

# Wait a moment for the application to be registered
sleep 5

# Sync the application to deploy it
echo -e "${YELLOW}Syncing ArgoCD application to deploy playground app...${NC}"
sudo argocd app sync playground-app

if [ $? -ne 0 ]; then
  echo -e "${YELLOW}Sync command returned an error, checking application status...${NC}"
fi

# Wait for the deployment to complete
echo -e "${YELLOW}Waiting for ArgoCD application to be healthy and synced...${NC}"
sudo argocd app wait playground-app --timeout 300

if [ $? -ne 0 ]; then
  echo -e "${YELLOW}Application may not be fully synced yet, checking manually...${NC}"
  sudo argocd app get playground-app
fi

# Display cluster status
echo -e "${YELLOW}=== Namespaces ===${NC}"
sudo kubectl get ns

echo -e "${YELLOW}=== Pods in dev namespace ===${NC}"
sudo kubectl get pods -n dev

echo -e "${YELLOW}=== Services in dev namespace ===${NC}"
sudo kubectl get svc -n dev

# Check if there are any resources deployed
RESOURCE_COUNT=$(sudo kubectl get all -n dev --no-headers 2>/dev/null | wc -l)
if [ "$RESOURCE_COUNT" -eq 0 ]; then
  echo -e "${RED}WARNING: No resources found in dev namespace!${NC}"
  echo -e "${YELLOW}The GitLab repository may be empty or contain no Kubernetes manifests.${NC}"
  echo -e "${YELLOW}Check the repository: http://localhost:8082/root/dbanfi_playground${NC}"
  exit 1
fi

# Wait for pods to be ready
echo -e "${YELLOW}=== Waiting for pods to be ready ===${NC}"
sudo kubectl wait --for=condition=Ready pods --all -n dev --timeout=120s

# Get the service details and set up port forwarding
SERVICE_NAME=$(sudo kubectl get svc -n dev -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
SERVICE_PORT=$(sudo kubectl get svc -n dev -o jsonpath='{.items[0].spec.ports[0].port}' 2>/dev/null)

if [ -n "$SERVICE_NAME" ] && [ -n "$SERVICE_PORT" ]; then
  echo -e "${YELLOW}=== Setting up port-forward to $SERVICE_NAME on port $SERVICE_PORT -> $SERVICE_PORT ===${NC}"
  nohup  $PWD/portForward.sh dev $SERVICE_NAME $SERVICE_PORT:$SERVICE_PORT >  $PWD/logs/playground-portforward.log 2>&1 &
  
  # Wait for port-forward to be fully established
  echo -e "${YELLOW}Waiting for port-forward to be ready...${NC}"
  sleep 5
  
  # Try to connect and verify it's working
  echo -e "${YELLOW}=== Testing application at http://localhost:$SERVICE_PORT ===${NC}"
  for i in {1..5}; do
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$SERVICE_PORT 2>/dev/null)
    if [ "$RESPONSE" != "000" ]; then
      echo -e "${GREEN}Connection established (HTTP $RESPONSE)${NC}"
      break
    fi
    echo -e "${YELLOW}Attempt $i: Waiting for connection...${NC}"
    sleep 2
  done
  
  # Display the actual content
  curl -s http://localhost:$SERVICE_PORT
  echo ""
  
else
  echo -e "${RED}No service found to test${NC}"
fi