#!/bin/bash
set -e

# Load credentials from .env file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
  source "$SCRIPT_DIR/.env"
  ROOT_PASSWORD="$GITLAB_PASSWORD"
else
  echo "Error: .env file not found in $SCRIPT_DIR"
  exit 1
fi

# Variables
PROJECT_NAME="dbanfi_playground"
MANIFESTS_DIR="../manifests"
TMP_DIR="/tmp/gitlab-repo-$PROJECT_NAME"
GITLAB_URL="http://localhost:8082"

echo "========================================="
echo "GitLab Repository Setup"
echo "========================================="
echo
echo "This script will create a GitLab project and push your manifests."
echo

echo "Waiting for GitLab to be ready..."
for i in {1..30}; do
  if curl -s -o /dev/null -w "%{http_code}" "$GITLAB_URL" | grep -q "200\|302"; then
    echo "✓ GitLab is ready!"
    break
  fi
  echo "Attempt $i/30: Waiting for GitLab..."
  sleep 2
done

echo "Verifying root user namespace setup..."
TOOLBOX_POD=$(sudo kubectl get pod -n gitlab -l app=toolbox -o jsonpath='{.items[0].metadata.name}')

sudo kubectl exec -n gitlab "$TOOLBOX_POD" -- gitlab-rails runner "
user = User.find_by_username('root')
if user.nil?
  puts '✗ ERROR: Root user not found!'
  exit 1
end

# Check if namespace exists - it may not be immediately linked
if user.namespace.nil?
  puts '⚠ Root user namespace not linked yet'
  puts '  Checking for existing root namespace...'
  
  # Find the namespace that should belong to root
  ns = Namespace.find_by(path: 'root')
  if ns
    puts '✓ Root namespace exists in database'
    puts '  The user can still create projects via API'
  else
    puts '✗ ERROR: No root namespace found in database'
    exit 1
  end
else
  puts '✓ Root user namespace verified: ' + user.namespace.path
end
" || {
  echo "⚠ Namespace verification had issues, but continuing..."
  echo "  The API may still work for creating projects"
}

echo "Generating Personal Access Token for API..."
TOKEN=$(sudo kubectl exec -n gitlab "$TOOLBOX_POD" -- gitlab-rails runner "
user = User.find_by_username('root')
token = user.personal_access_tokens.create(
  name: 'automation-token-' + Time.now.to_i.to_s,
  scopes: [:api, :write_repository, :read_repository],
  expires_at: 365.days.from_now
)
if token.persisted?
  puts token.token
else
  STDERR.puts 'Token creation failed: ' + token.errors.full_messages.join(', ')
  exit 1
end
" 2>&1 | grep -E '^glpat-')

if [ -z "$TOKEN" ] || ! echo "$TOKEN" | grep -q "^glpat-"; then
  echo "✗ Failed to generate access token"
  exit 1
fi

echo "✓ Access token generated"

echo "Creating project '$PROJECT_NAME'..."
# Use token-based authentication for API
RESPONSE=$(curl -s -w "\n%{http_code}" -H "PRIVATE-TOKEN: $TOKEN" -X POST "$GITLAB_URL/api/v4/projects" \
  --data "name=$PROJECT_NAME" \
  --data "path=$PROJECT_NAME" \
  --data "visibility=private")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

if [ "$HTTP_CODE" = "201" ]; then
  echo "✓ Project created successfully!"
elif [ "$HTTP_CODE" = "400" ]; then
  echo "⚠ Project may already exist, continuing..."
else
  echo "✗ API call returned HTTP $HTTP_CODE"
  echo "$RESPONSE" | head -n-1
  exit 1
fi

echo "Cloning repository..."
rm -rf "$TMP_DIR"

# Run git commands as actual user if using sudo
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
  sudo -u "$SUDO_USER" git clone "http://root:$TOKEN@localhost:8082/root/$PROJECT_NAME.git" "$TMP_DIR"
else
  git clone "http://root:$TOKEN@localhost:8082/root/$PROJECT_NAME.git" "$TMP_DIR"
fi

echo "Copying manifests..."
cp "$MANIFESTS_DIR"/deployment.yaml "$MANIFESTS_DIR"/service.yaml "$TMP_DIR/"

# Fix ownership of copied files if running with sudo
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
  chown -R "$SUDO_USER:$SUDO_USER" "$TMP_DIR"
  echo "✓ Repository ownership set to $SUDO_USER"
fi

cd "$TMP_DIR"
echo "Configuring git user..."
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
  sudo -u "$SUDO_USER" git config user.email "admin@example.com"
  sudo -u "$SUDO_USER" git config user.name "Administrator"
else
  git config user.email "admin@example.com"
  git config user.name "Administrator"
fi

echo "Committing and pushing initial v1..."
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
  sudo -u "$SUDO_USER" git add .
  sudo -u "$SUDO_USER" git commit -m "Initial v1 deployment (playground app)"
  sudo -u "$SUDO_USER" git push origin main || sudo -u "$SUDO_USER" git push origin master:main
else
  git add .
  git commit -m "Initial v1 deployment (playground app)"
  git push origin main || git push origin master:main
fi

echo
echo "========================================="
echo "✓ Repository created and manifests pushed!"
echo "========================================="
echo "Repository URL: $GITLAB_URL/root/$PROJECT_NAME"
echo