#!/usr/bin/env ruby
require 'active_record'

# Load password from ENV, fall back to file or default
password_file = '/etc/gitlab/initial_root_password/password'
root_password = ENV['GITLAB_PASSWORD'] || (File.exist?(password_file) ? File.read(password_file).strip : 'changeme')

# Connect to database (assumes Rails environment)
# ActiveRecord::Base.establish_connection(...)

# Check if namespace exists
existing_namespace = Namespace.find_by(path: 'root')
if existing_namespace
  puts 'Namespace already exists from GitLab initialization'
else
  puts 'Creating namespace via database...'
  ActiveRecord::Base.connection.execute(
    "INSERT INTO namespaces (id, name, path, owner_id, type, created_at, updated_at, visibility_level, shared_runners_enabled, project_creation_level, organization_id)
     VALUES (1, 'Administrator', 'root', 1, 'User', NOW(), NOW(), 20, true, 20, 1)
     ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name"
  )
  existing_namespace = Namespace.find(1)
  puts 'Namespace created via database'
end

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
    puts 'Root user created'
  else
    puts 'Failed to create root user: ' + user.errors.full_messages.join(', ')
    exit 1
  end
else
  puts 'Root user already exists'
end

user.password = root_password
user.password_confirmation = root_password
user.save(validate: false)

user.reload
if user.valid_password?(root_password)
  puts 'Root user has functional password'
else
  puts 'Password verification failed'
end

if user.namespace
  puts 'Root user has namespace: ' + user.namespace.path
else
  puts 'Namespace not linked via association, but exists in database'
end

puts 'Root user setup completed'
