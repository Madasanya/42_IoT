#!/bin/bash
set -e

# Load credentials from .env file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
  source "$SCRIPT_DIR/.env"
  PASSWORD="$GITLAB_PASSWORD"
else
  echo "Error: .env file not found in $SCRIPT_DIR"
  exit 1
fi

echo "=== GitLab Root Password Setup ==="
echo "Using password from .env file"

echo "Creating namespace and pre-defined root password secret..."

sudo kubectl create namespace gitlab --dry-run=client -o yaml | sudo kubectl apply -f -

sudo kubectl create secret generic gitlab-gitlab-initial-root-password \
  --namespace gitlab \
  --from-literal=password="$PASSWORD" \
  --dry-run=client -o yaml | sudo kubectl apply -f -

echo "Pre-pulling critical GitLab images to avoid timeout issues..."
echo "This may take several minutes depending on network speed..."
GITLAB_VERSION="v18.7.1"
CRITICAL_IMAGES=(
  "registry.gitlab.com/gitlab-org/build/cng/gitlab-webservice-ce:${GITLAB_VERSION}"
  "registry.gitlab.com/gitlab-org/build/cng/gitlab-toolbox-ce:${GITLAB_VERSION}"
  "registry.gitlab.com/gitlab-org/build/cng/gitlab-sidekiq-ce:${GITLAB_VERSION}"
  "registry.gitlab.com/gitlab-org/build/cng/gitaly:${GITLAB_VERSION}"
  "registry.gitlab.com/gitlab-org/build/cng/gitlab-shell:${GITLAB_VERSION}"
)

for image in "${CRITICAL_IMAGES[@]}"; do
  echo "Pulling $image..."
  if ! sudo k3d image import "$image" -c mycluster 2>/dev/null; then
    # If k3d import fails, try direct docker pull
    docker pull "$image" 2>/dev/null || echo "Warning: Failed to pre-pull $image"
  fi
done

echo "Deploying GitLab with your custom root password..."
helm repo add gitlab https://charts.gitlab.io/ 2>/dev/null || helm repo add gitlab https://charts.gitlab.io/ --force-update
helm repo update
helm upgrade --install gitlab gitlab/gitlab \
  --namespace gitlab \
  --values ../confs/gitlab-values.yaml \
  --set global.initialRootPassword.secret=gitlab-gitlab-initial-root-password \
  --set global.initialRootPassword.key=password \
  --set imagePullPolicy=IfNotPresent \
  --timeout 60m

echo "Waiting for GitLab webservice rollout (this may take a while due to image pulls)..."
sudo kubectl rollout status deployment/gitlab-webservice-default -n gitlab --timeout=60m

echo "Waiting for GitLab to fully initialize (this may take a few minutes)..."
sleep 60

echo "Creating root user in GitLab..."

TOOLBOX_POD=$(sudo kubectl get pod -n gitlab -l app=toolbox -o jsonpath='{.items[0].metadata.name}')
# Copy to /tmp to avoid permission issues
sudo kubectl cp "$SCRIPT_DIR/setup_root_user.rb" gitlab/$TOOLBOX_POD:/tmp/setup_root_user.rb
sudo kubectl exec -n gitlab "$TOOLBOX_POD" -- gitlab-rails runner /tmp/setup_root_user.rb

if [ $? -eq 0 ]; then
  echo "✓ Root user setup completed"
else
  echo "✗ Root user creation failed"
  exit 1
fi

echo "Fixing database sequences to prevent future conflicts..."
# Copy and run fix_db_sequences.rb in the toolbox pod
sudo kubectl cp "$SCRIPT_DIR/fix_db_sequences.rb" gitlab/$TOOLBOX_POD:/tmp/fix_db_sequences.rb
sudo kubectl exec -n gitlab "$TOOLBOX_POD" -- gitlab-rails runner /tmp/fix_db_sequences.rb

# Forward the port in the background and suppress all output
nohup $PWD/portForward.sh gitlab gitlab-webservice-default 8082:8181 > $PWD/logs/gitlab-portforward.log 2>&1 &

# Wait for port forwarding to be ready
sleep 5

echo
echo "========================================="
echo "GitLab deployed successfully!"
echo "========================================="
echo "Credentials:"
echo "  URL: http://localhost:8082"
echo "  Username: root"
echo "  Password: [the password you set earlier]"
echo
echo "Port-forward started automatically in background."
echo "You can now log in to GitLab!"
echo "========================================="