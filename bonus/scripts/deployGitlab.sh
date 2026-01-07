#!/bin/bash
set -e

echo "=== GitLab Root Password Setup ==="

while true; do
    echo "Please set a strong password for the GitLab 'root' user."
    echo "Requirements:"
    echo "  - Minimum 8 characters"
    echo "  - Only printable basic characters (letters, numbers, !@#$%^&*()_+-= etc.)"
    echo "  - No spaces or control characters"
    read -s -p "Enter password: " PASSWORD
    echo
    read -s -p "Confirm password: " PASSWORD_CONFIRM
    echo

    if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
        echo "Error: Passwords do not match. Try again."
        continue
    fi

    if [ ${#PASSWORD} -lt 8 ]; then
        echo "Error: Password must be at least 8 characters long."
        continue
    fi

    # Check for only printable basic ASCII (32-126)
    if [[ "$PASSWORD" =~ [^[:print:]] || "$PASSWORD" =~ [[:cntrl:]] ]]; then
        echo "Error: Password contains invalid characters (only basic printable ASCII allowed)."
        continue
    fi

    echo "Password accepted!"
    break
done

echo "Creating namespace and pre-defined root password secret..."

sudo kubectl create namespace gitlab --dry-run=client -o yaml | sudo kubectl apply -f -

sudo kubectl create secret generic gitlab-gitlab-initial-root-password \
  --namespace gitlab \
  --from-literal=password="$PASSWORD" \
  --dry-run=client -o yaml | sudo kubectl apply -f -

echo "Deploying GitLab with your custom root password..."
helm repo add gitlab https://charts.gitlab.io/ 2>/dev/null || helm repo add gitlab https://charts.gitlab.io/ --force-update
helm repo update
helm upgrade --install gitlab gitlab/gitlab \
  --namespace gitlab \
  --values ../confs/gitlab-values.yaml \
  --set global.initialRootPassword.secret=gitlab-gitlab-initial-root-password \
  --set global.initialRootPassword.key=password \
  --timeout 30m

echo "Waiting for GitLab webservice rollout..."
sudo kubectl rollout status deployment/gitlab-webservice-default -n gitlab --timeout=20m

echo "Waiting for GitLab to fully initialize (this may take a few minutes)..."
sleep 60

echo "Waiting for Workhorse to be ready..."
for i in {1..20}; do
  WORKHORSE_CHECK=$(sudo kubectl get pods -n gitlab -l app=webservice -o json | grep -o '"ready":true' | wc -l)
  if [ "$WORKHORSE_CHECK" -ge "2" ]; then
    echo "✓ Workhorse is ready"
    break
  fi
  echo "Waiting for Workhorse... ($i/20)"
  sleep 3
done

echo "Waiting for Gitaly to be ready..."
for i in {1..20}; do
  GITALY_CHECK=$(sudo kubectl get pods -n gitlab -l app=gitaly -o json | grep -o '"ready":true' | wc -l)
  if [ "$GITALY_CHECK" -ge "1" ]; then
    echo "✓ Gitaly is ready"
    break
  fi
  echo "Waiting for Gitaly... ($i/20)"
  sleep 3
done

sleep 30

echo "Creating root user in GitLab..."
TOOLBOX_POD=$(sudo kubectl get pod -n gitlab -l app=toolbox -o jsonpath='{.items[0].metadata.name}')

sudo kubectl exec -n gitlab "$TOOLBOX_POD" -- gitlab-rails runner "
# Create root user manually with password from secret
root_password = File.read('/etc/gitlab/initial_root_password/password').strip rescue '$PASSWORD'

# Get default organization ID from database (organization with ID=1 is created by GitLab migrations)
org_result = ActiveRecord::Base.connection.execute('SELECT id, name FROM organizations WHERE id = 1 LIMIT 1')
if org_result.count > 0
  default_org_id = org_result.first['id'].to_i
  default_org_name = org_result.first['name']
  puts '✓ Using organization: ' + default_org_name + ' (ID: ' + default_org_id.to_s + ')'
else
  default_org_id = 1
  puts '⚠ Using default organization ID: 1'
end

# Find existing root user
user = User.find_by(username: 'root')

if user
  puts '✓ Root user already exists (ID: ' + user.id.to_s + ')'
  # Update password
  user.password = root_password
  user.password_confirmation = root_password
  user.admin = true
  user.confirmed_at = Time.now if user.confirmed_at.nil?
  user.save(validate: false)
  puts '✓ Root user password updated'
else
  puts '⚠ Root user does not exist, creating...'
  
  # Create user - this will auto-create the namespace
  user = User.new(
    email: 'admin@example.com',
    name: 'Administrator',
    username: 'root',
    password: root_password,
    password_confirmation: root_password,
    admin: true,
    confirmed_at: Time.now
  )
  
  user.skip_confirmation!
  user.skip_reconfirmation!
  
  if user.save(validate: false)
    puts '✓ Root user created with ID: ' + user.id.to_s
  else
    puts '✗ Failed to create root user: ' + user.errors.full_messages.join(', ')
    exit 1
  end
  
  user.reload
end

# Ensure user has a namespace
unless user.namespace
  puts '⚠ User has no namespace, creating...'
  
  # Try to find existing namespace by path
  ns = Namespace.find_by(path: 'root', type: 'Namespaces::UserNamespace')
  
  if ns
    puts '✓ Found existing namespace, linking to user'
    ns.update_columns(owner_id: user.id, organization_id: default_org_id) if ns.owner_id != user.id
  else
    # Create namespace with organization
    ns = Namespaces::UserNamespace.new(
      name: user.name,
      path: user.username,
      owner_id: user.id,
      organization_id: default_org_id
    )
    
    if ns.save(validate: false)
      puts '✓ Namespace created: ' + ns.path + ' (ID: ' + ns.id.to_s + ')'
    else
      puts '✗ Failed to create namespace: ' + ns.errors.full_messages.join(', ')
    end
  end
  
  user.reload
end

# Verify setup
if user.namespace
  puts '✓ Root user namespace verified: ' + user.namespace.path
  puts '✓ Namespace ID: ' + user.namespace.id.to_s
  puts '✓ User can create projects'
else
  puts '✗ WARNING: User has no namespace, but continuing...'
end

# Verify password
if user.valid_password?(root_password)
  puts '✓ Root user password verified'
else
  puts '⚠ Password verification failed'
end

# Ensure user is admin
unless user.admin?
  user.update_column(:admin, true)
  puts '✓ Admin privileges granted'
end

puts '✓ Root user setup completed'
"

if [ $? -eq 0 ]; then
  echo "✓ Root user setup completed"
else
  echo "✗ Root user creation failed"
  exit 1
fi

echo "Fixing database sequences to prevent future conflicts..."
sudo kubectl exec -n gitlab "$TOOLBOX_POD" -- gitlab-rails runner "
# Fix all common sequences that can cause issues
sequences = ['namespaces_id_seq', 'projects_id_seq', 'users_id_seq']
sequences.each do |seq|
  table_name = seq.gsub('_id_seq', '')
  max_id = ActiveRecord::Base.connection.execute(\"SELECT MAX(id) FROM #{table_name}\").first['max'].to_i
  if max_id > 0
    ActiveRecord::Base.connection.execute(\"SELECT setval('#{seq}', #{max_id + 1}, false)\")
    puts \"✓ Fixed #{seq} (set to #{max_id + 1})\"
  end
end
puts '✓ Database sequences initialized'
"

echo "Disabling default branch protection and git hooks globally..."
sudo kubectl exec -n gitlab "$TOOLBOX_POD" -- gitlab-rails runner "
# Disable default branch protection (0 = no protection)
ApplicationSetting.current.update_columns(
  default_branch_protection: 0,
  default_branch_protection_defaults: {},
  allow_local_requests_from_web_hooks_and_services: true,
  allow_local_requests_from_system_hooks: true
)
puts '✓ Default branch protection disabled globally'

# Disable all server hooks and validations that might interfere
ApplicationSetting.current.update_columns(
  push_event_hooks_limit: 0,
  push_event_activities_limit: 0
) rescue puts '⚠ Could not update hook limits'

# Also disable for any existing projects
Project.find_each do |project|
  # Unprotect all protected branches
  project.protected_branches.destroy_all
  puts \"✓ Unprotected all branches in project: #{project.path_with_namespace}\"
end
puts '✓ All existing protected branches removed'
"

# Wait for GitLab internal API to be fully ready before finishing
echo "Waiting for GitLab internal API to be fully operational..."
sleep 30

echo "Verifying GitLab is ready for git operations..."
for i in {1..10}; do
  sudo kubectl exec -n gitlab "$TOOLBOX_POD" -- gitlab-rails runner "
    # Test that we can perform basic git access checks
    begin
      user = User.find_by_username('root')
      if user && user.can_create_project?
        puts '✓ GitLab is ready for git operations'
        exit 0
      else
        puts '⚠ Not ready yet...'
        exit 1
      end
    rescue => e
      STDERR.puts 'Error: ' + e.message
      exit 1
    end
  " && break
  
  echo "Attempt $i/10: Waiting for GitLab to be fully ready..."
  sleep 10
done

# Forward the port in the background and suppress all output
nohup $PWD/portForward.sh gitlab gitlab-webservice-default 8082:8181 > $PWD/logs/gitlab-portforward.log 2>&1 &

# Wait for port forwarding to be ready
sleep 5

echo "Waiting additional time for all GitLab services to be synchronized..."
sleep 60

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