#!/bin/bash

# Ensure cleanup of port-forward on script exit
cleanup() {
  echo "Cleaning up port-forward..."
  sudo pkill -f "kubectl port-forward svc/argocd-server" 2>/dev/null
  curl -kLs "https://localhost:8081" 1>/dev/null 2>/dev/null
}
trap cleanup EXIT

# Create the Argo CD namespace and install:
sudo kubectl create namespace argocd
sudo kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for pods to start
sudo kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

# Get the initial admin password from the secret
ARGOCD_PASSWORD=$(sudo kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "Initial ArgoCD password: $ARGOCD_PASSWORD"

# Forward the port in the background and suppress all output
#sudo kubectl port-forward svc/argocd-server -n argocd 8081:443 >/dev/null 2>&1 &
nohup /home/mamuller/42_IoT/p3/scripts/portForward.sh argocd argocd-server 8081:443 > ./logs/argocd-portforward.log 2>&1 &
PORT_FORWARD_PID=$!

# Wait for port forwarding to be ready
sleep 5

# Login to ArgoCD using the initial password
sudo argocd login localhost:8081 --insecure --username admin --password "$ARGOCD_PASSWORD"

# Change password - prompt user for new password or use environment variable
if [ -z "$ARGOCD_NEW_PASSWORD" ]; then
  while true; do
    echo "Enter new password for ArgoCD admin (must be exactly 8 alphanumeric characters):"
    read -s NEW_PASSWORD
    echo
    
    # Check if password is exactly 8 characters
    if [ ${#NEW_PASSWORD} -ne 8 ]; then
      echo "Error: Password must be exactly 8 characters. Please try again."
      continue
    fi
    
    # Check if password contains only alphanumeric characters (0-9, a-z, A-Z)
    if [[ ! "$NEW_PASSWORD" =~ ^[a-zA-Z0-9]+$ ]]; then
      echo "Error: Password must contain only alphanumeric characters (0-9, a-z, A-Z). Please try again."
      continue
    fi
    
    echo "Confirm new password:"
    read -s NEW_PASSWORD_CONFIRM
    echo
    
    if [ "$NEW_PASSWORD" != "$NEW_PASSWORD_CONFIRM" ]; then
      echo "Passwords do not match. Please try again."
      continue
    fi
    
    break
  done
else
  NEW_PASSWORD="$ARGOCD_NEW_PASSWORD"
  # Validate environment variable password as well
  if [ ${#NEW_PASSWORD} -ne 8 ]; then
    echo "Error: ARGOCD_NEW_PASSWORD must be exactly 8 characters"
    exit 1
  fi
  if [[ ! "$NEW_PASSWORD" =~ ^[a-zA-Z0-9]+$ ]]; then
    echo "Error: ARGOCD_NEW_PASSWORD must contain only alphanumeric characters (0-9, a-z, A-Z)"
    exit 1
  fi
fi

sudo argocd account update-password --current-password "$ARGOCD_PASSWORD" --new-password "$NEW_PASSWORD"

echo "ArgoCD password changed successfully"


# to activate the port forwarding again after script ends, run:
# sudo kubectl port-forward svc/argocd-server -n argocd 8081:443

# to view argocd UI, open a browser and go to:
# https://localhost:8081

# Note: The port-forward will be automatically cleaned up when the script exits due to the trap set earlier.