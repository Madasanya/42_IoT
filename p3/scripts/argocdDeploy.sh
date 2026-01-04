#!/bin/bash

# Create the dev namespace where the application will be deployed
sudo kubectl create namespace dev 2>/dev/null || echo "Namespace 'dev' already exists"

# Login to ArgoCD (using the password set in step03)
# If ARGOCD_PASSWORD environment variable is not set, prompt for it
if [ -z "$ARGOCD_PASSWORD" ]; then
  echo "Enter ArgoCD admin password:"
  read -s ARGOCD_PASSWORD
  echo
fi

sudo argocd login localhost:8081 --insecure --username admin --password "$ARGOCD_PASSWORD"

# Create the ArgoCD application from the configuration file
sudo kubectl apply -f $PWD/../confs/application.yaml

# Wait a moment for the application to be registered
sleep 5

# Sync the application to deploy it
sudo argocd app sync playground-app

# Wait for the deployment to complete
sudo argocd app wait playground-app --timeout 300

# Display cluster status
echo "=== Namespaces ==="
sudo kubectl get ns

echo "=== Pods in dev namespace ==="
sudo kubectl get pods -n dev

echo "=== Services in dev namespace ==="
sudo kubectl get svc -n dev

# Check if there are any resources deployed
RESOURCE_COUNT=$(sudo kubectl get all -n dev --no-headers 2>/dev/null | wc -l)
if [ "$RESOURCE_COUNT" -eq 0 ]; then
  echo "WARNING: No resources found in dev namespace!"
  echo "The GitHub repository may be empty or contain no Kubernetes manifests."
  echo "Check the repository: https://github.com/mr-bammby/dbanfi_playground.git"
  exit 1
fi

# Wait for pods to be ready
echo "=== Waiting for pods to be ready ==="
sudo kubectl wait --for=condition=Ready pods --all -n dev --timeout=120s

# Get the service details and set up port forwarding
SERVICE_NAME=$(sudo kubectl get svc -n dev -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
SERVICE_PORT=$(sudo kubectl get svc -n dev -o jsonpath='{.items[0].spec.ports[0].port}' 2>/dev/null)

if [ -n "$SERVICE_NAME" ] && [ -n "$SERVICE_PORT" ]; then
  echo "=== Setting up port-forward to $SERVICE_NAME on port $SERVICE_PORT -> $SERVICE_PORT ==="
  nohup  $PWD/portForward.sh dev $SERVICE_NAME $SERVICE_PORT:$SERVICE_PORT >  $PWD/logs/playground-portforward.log 2>&1 &
  
  # Wait for port-forward to be fully established
  echo "Waiting for port-forward to be ready..."
  sleep 5
  
  # Try to connect and verify it's working
  echo "=== Testing application at http://localhost:$SERVICE_PORT ==="
  for i in {1..5}; do
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$SERVICE_PORT 2>/dev/null)
    if [ "$RESPONSE" != "000" ]; then
      echo "Connection established (HTTP $RESPONSE)"
      break
    fi
    echo "Attempt $i: Waiting for connection..."
    sleep 2
  done
  
  # Display the actual content
  curl -s http://localhost:$SERVICE_PORT
  echo ""
  
else
  echo "No service found to test"
fi