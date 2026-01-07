#!/bin/bash
set -e

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
read -s -p "Enter GitLab root password: " ROOT_PASSWORD
echo
echo

echo "Waiting for GitLab to be ready..."
for i in {1..30}; do
  if curl -s -o /dev/null -w "%{http_code}" "$GITLAB_URL" | grep -q "200\|302"; then
    echo "✓ GitLab webservice is ready!"
    break
  fi
  echo "Attempt $i/30: Waiting for GitLab webservice..."
  sleep 2
done

# Additional wait to ensure all internal services are synchronized
echo "Waiting for all GitLab internal services to stabilize..."
sleep 60

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

# Verify user can create projects
unless user.can_create_project?
  puts '⚠ WARNING: User may not be able to create projects'
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
echo "Disabling branch protection globally..."
sudo kubectl exec -n gitlab "$TOOLBOX_POD" -- gitlab-rails runner "
ApplicationSetting.current.update_columns(default_branch_protection: 0)
puts '✓ Default branch protection disabled'
"
echo "Checking if project '$PROJECT_NAME' exists..."
# Check if project exists first
PROJECT_CHECK=$(curl -s -H "PRIVATE-TOKEN: $TOKEN" "$GITLAB_URL/api/v4/projects/root%2F$PROJECT_NAME" -o /dev/null -w "%{http_code}")

if [ "$PROJECT_CHECK" = "200" ]; then
  echo "✓ Project already exists, will update it"
  PROJECT_EXISTS=true
else
  echo "Creating project '$PROJECT_NAME'..."
  # Use token-based authentication for API
  RESPONSE=$(curl -s -w "\n%{http_code}" -H "PRIVATE-TOKEN: $TOKEN" -X POST "$GITLAB_URL/api/v4/projects" \
    -H "Content-Type: application/json" \
    --data "{\"name\":\"$PROJECT_NAME\",\"path\":\"$PROJECT_NAME\",\"visibility\":\"private\",\"initialize_with_readme\":false}")
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  
  if [ "$HTTP_CODE" = "201" ]; then
    echo "✓ Project created successfully!"
    PROJECT_EXISTS=true
    echo "Waiting for project to be fully initialized..."
    
    # Wait for project to be truly ready with proper repository
    for i in {1..20}; do
      PROJECT_STATUS=$(curl -s -H "PRIVATE-TOKEN: $TOKEN" "$GITLAB_URL/api/v4/projects/root%2F$PROJECT_NAME" | grep -o '"empty_repo":[^,}]*' || echo "")
      if echo "$PROJECT_STATUS" | grep -q "empty_repo"; then
        echo "✓ Project repository initialized (attempt $i)"
        break
      fi
      echo "Waiting for repository initialization (attempt $i/20)..."
      sleep 2
    done
    
    sleep 5
  else
    echo "✗ API call returned HTTP $HTTP_CODE"
    echo "$RESPONSE" | head -n-1
    exit 1
  fi
fi

echo "Cloning repository..."
rm -rf "$TMP_DIR"
git clone "http://root:$TOKEN@localhost:8082/root/$PROJECT_NAME.git" "$TMP_DIR"

# Configure git safe directory to avoid permission warnings
git config --global --add safe.directory "$TMP_DIR"

# Fix ownership so the actual user (not root) can work without sudo
# This is critical - git clone as root creates files owned by root
if [ -n "$SUDO_USER" ]; then
  echo "Fixing repository ownership for user $SUDO_USER..."
  chown -R $SUDO_USER:$SUDO_USER "$TMP_DIR"
else
  # If not running via sudo, fix ownership to current user anyway
  ACTUAL_USER=$(logname 2>/dev/null || echo $USER)
  if [ "$ACTUAL_USER" != "root" ]; then
    echo "Fixing repository ownership for user $ACTUAL_USER..."
    chown -R $ACTUAL_USER:$ACTUAL_USER "$TMP_DIR"
  fi
fi

echo "Copying manifests..."
cp "$MANIFESTS_DIR"/deployment.yaml "$MANIFESTS_DIR"/service.yaml "$TMP_DIR/"

cd "$TMP_DIR"
echo "Configuring git user..."
git config user.email "admin@example.com"
git config user.name "Administrator"

# Disable branch protection for this specific project
echo "Disabling branch protection for project..."
curl -s -X PUT -H "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB_URL/api/v4/projects/root%2F$PROJECT_NAME" \
  --data "only_allow_merge_if_pipeline_succeeds=false" \
  --data "only_allow_merge_if_all_discussions_are_resolved=false" > /dev/null

# Unprotect main branch if it exists
echo "Unprotecting main branch..."
curl -s -X DELETE -H "PRIVATE-TOKEN: $TOKEN" \
  "$GITLAB_URL/api/v4/projects/root%2F$PROJECT_NAME/protected_branches/main" > /dev/null 2>&1 || true

# Disable push rules and ensure project is ready for git operations
echo "Configuring project for git operations..."
sudo kubectl exec -n gitlab "$TOOLBOX_POD" -- gitlab-rails runner "
project = Project.find_by_full_path('root/$PROJECT_NAME')
if project
  # Ensure project settings allow pushes
  begin
    project.project_setting.update_columns(
      only_allow_merge_if_pipeline_succeeds: false,
      only_allow_merge_if_all_discussions_are_resolved: false
    )
  rescue => e
    puts '⚠ Could not update project settings: ' + e.message
  end
  
  # Destroy any push rules
  begin
    project.push_rule.destroy if project.push_rule
  rescue => e
    # Ignore - push rules might not exist
  end
  
  # Force repository initialization
  begin
    unless project.repository_exists?
      project.create_repository
      puts '✓ Repository initialized'
    end
  rescue => e
    puts '⚠ Repository already exists or error: ' + e.message
  end
  
  puts '✓ Project configured to allow all pushes'
else
  puts '⚠ Could not find project'
end
"

echo "Waiting for repository to be fully initialized..."
sleep 10

echo "Committing and pushing initial v1..."
git add .
git commit -m "Initial v1 deployment (playground app)"

# Try pushing with better error handling
echo "Pushing to GitLab..."
if ! git push origin main; then
  echo "⚠ Push to main failed, trying master branch..."
  
  # Rename branch to main if needed
  git branch -M main
  
  # Try push again with verbose output
  if ! GIT_CURL_VERBOSE=1 GIT_TRACE=1 git push -u origin main 2>&1 | tee /tmp/git-push-debug.log; then
    echo "✗ Push failed. Debug info:"
    echo "Git remote:"
    git remote -v
    echo
    echo "Last 20 lines of GitLab Gitaly logs:"
    sudo kubectl logs -n gitlab -l app=gitaly --tail=20 || true
    echo
    echo "Last 20 lines of GitLab webservice logs:"
    sudo kubectl logs -n gitlab -l app=webservice --tail=20 || true
    exit 1
  fi
fi

echo
echo "========================================="
echo "✓ Repository created and manifests pushed!"
echo "========================================="
echo "Repository URL: $GITLAB_URL/root/$PROJECT_NAME"
echo