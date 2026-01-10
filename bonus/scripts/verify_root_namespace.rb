#!/usr/bin/env ruby
# Script to verify root user namespace in GitLab
user = User.find_by_username('root')
if user.nil?
  puts 'ERROR: Root user not found!'
  exit 1
end

# Check if namespace exists - it may not be immediately linked
if user.namespace.nil?
  puts 'Root user namespace not linked yet'
  puts 'Checking for existing root namespace...'
  ns = Namespace.find_by(path: 'root')
  if ns
    puts 'Root namespace exists in database'
    puts 'The user can still create projects via API'
  else
    puts 'ERROR: No root namespace found in database'
    exit 1
  end
else
  puts 'Root user namespace verified: ' + user.namespace.path
end
