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

echo "Creating root user in GitLab..."
TOOLBOX_POD=$(sudo kubectl get pod -n gitlab -l app=toolbox -o jsonpath='{.items[0].metadata.name}')

sudo kubectl exec -n gitlab "$TOOLBOX_POD" -- gitlab-rails runner "
# Create root user manually with password from secret
root_password = File.read('/etc/gitlab/initial_root_password/password').strip rescue '$PASSWORD'

# Check if namespace already exists (created by migrations)
existing_namespace = Namespace.find_by(path: 'root')
if existing_namespace
  puts '✓ Namespace already exists from GitLab initialization'
end

# Use direct database insert for namespace if it doesn't exist
unless existing_namespace
  puts '⚠ Creating namespace via database...'
  # Use raw SQL to bypass all validations and constraints
  ActiveRecord::Base.connection.execute(
    \"INSERT INTO namespaces (id, name, path, owner_id, type, created_at, updated_at, visibility_level, shared_runners_enabled, project_creation_level, organization_id)
     VALUES (1, 'Administrator', 'root', 1, 'User', NOW(), NOW(), 20, true, 20, 1)
     ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name\"
  )
  existing_namespace = Namespace.find(1)
  puts '✓ Namespace created via database'
end

# Create user - will link to namespace
user = User.find_by(username: 'root')
unless user
  user = User.new(
    id: 1,
    email: 'admin@example.com',
    name: 'Administrator',
    username: 'root',
    password: root_password,
    password_confirmation: root_password,
    admin: true
  )
  user.skip_confirmation!
  user.skip_reconfirmation!

  if user.save(validate: false)
    puts '✓ Root user created'
  else
    puts '✗ Failed to create root user: ' + user.errors.full_messages.join(', ')
    exit 1
  end
else
  puts '✓ Root user already exists'
end

# Set password (in case user existed but password wasn't set)
user.password = root_password
user.password_confirmation = root_password
user.save(validate: false)

# Verify password works
user.reload
if user.valid_password?(root_password)
  puts '✓ Root user has functional password'
else
  puts '⚠ Password verification failed'
end

# Verify namespace
if user.namespace
  puts '✓ Root user has namespace: ' + user.namespace.path
else
  puts '⚠ Namespace not linked via association, but exists in database'
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