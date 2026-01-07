#!/bin/bash

# Create the dev namespace where the application will be deployed
sudo kubectl create namespace dev 2>/dev/null || echo "Namespace 'dev' already exists"

# Retrieve ArgoCD admin password - try secret first, then prompt
if [ -z "$ARGOCD_PASSWORD" ]; then
  echo "Attempting to retrieve ArgoCD admin password from Kubernetes secret..."
  ARGOCD_PASSWORD=$(sudo kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null)
  
  if [ -z "$ARGOCD_PASSWORD" ]; then
    echo "⚠ Could not retrieve password from secret (may have been reset)"
    echo "Please enter ArgoCD admin password:"
    read -s -r ARGOCD_PASSWORD
    echo
  else
    echo "✓ ArgoCD password retrieved from secret"
  fi
fi

# Login to ArgoCD
echo "Logging into ArgoCD..."
LOGIN_OUTPUT=$(sudo argocd login localhost:8081 --insecure --username admin --password "$ARGOCD_PASSWORD" 2>&1)
LOGIN_EXIT=$?

if [ $LOGIN_EXIT -ne 0 ]; then
  echo "✗ Login failed with retrieved password"
  echo "Please enter ArgoCD admin password:"
  read -s -r ARGOCD_PASSWORD
  echo
  
  echo "Retrying login..."
  sudo argocd login localhost:8081 --insecure --username admin --password "$ARGOCD_PASSWORD"
  
  if [ $? -ne 0 ]; then
    echo "✗ ArgoCD login failed"
    exit 1
  fi
fi

echo "✓ Successfully logged into ArgoCD"

# Generate GitLab access token for ArgoCD
echo "Generating GitLab access token for ArgoCD..."
TOOLBOX_POD=$(sudo kubectl get pod -n gitlab -l app=toolbox -o jsonpath='{.items[0].metadata.name}')

GITLAB_TOKEN=$(sudo kubectl exec -n gitlab "$TOOLBOX_POD" -- gitlab-rails runner "
user = User.find_by_username('root')
token = user.personal_access_tokens.create(
  name: 'argocd-token-' + Time.now.to_i.to_s,
  scopes: [:read_repository, :write_repository],
  expires_at: 365.days.from_now
)
if token.persisted?
  puts token.token
else
  STDERR.puts 'Token creation failed: ' + token.errors.full_messages.join(', ')
  exit 1
end
" 2>&1 | grep -E '^glpat-')

if [ -z "$GITLAB_TOKEN" ] || ! echo "$GITLAB_TOKEN" | grep -q "^glpat-"; then
  echo "✗ Failed to generate GitLab access token"
  exit 1
fi

echo "✓ GitLab access token generated"

# Add GitLab repository to ArgoCD with credentials
echo "Adding GitLab repository to ArgoCD..."
sudo argocd repo add http://gitlab-webservice-default.gitlab.svc:8181/root/dbanfi_playground.git \
  --username root \
  --password "$GITLAB_TOKEN" \
  --insecure-skip-server-verification

if [ $? -ne 0 ]; then
  echo "⚠ Repository add command returned an error, but it may already be added"
else
  echo "✓ Repository added to ArgoCD"
fi

# Create the ArgoCD application from the configuration file
echo "Create ArgoCD application for playground app..."
sudo kubectl apply -f $PWD/../confs/application.yaml

# Wait a moment for the application to be registered
sleep 5

# Sync the application to deploy it
echo "Syncing ArgoCD application to deploy playground app..."
sudo argocd app sync playground-app

if [ $? -ne 0 ]; then
  echo "⚠ Sync command returned an error, checking application status..."
fi

# Wait for the deployment to complete
echo "Waiting for ArgoCD application to be healthy and synced..."
sudo argocd app wait playground-app --timeout 300

if [ $? -ne 0 ]; then
  echo "⚠ Application may not be fully synced yet, checking manually..."
  sudo argocd app get playground-app
fi

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
  echo "The GitLab repository may be empty or contain no Kubernetes manifests."
  echo "Check the repository: http://localhost:8082/root/dbanfi_playground"
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