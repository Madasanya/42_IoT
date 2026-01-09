#!/usr/bin/env ruby
# Script to create a GitLab Personal Access Token
# Usage: create_gitlab_token.rb <token_name_prefix> <scopes_comma_separated>
# Example: create_gitlab_token.rb "automation-token" "api,write_repository,read_repository"

if ARGV.length < 2
  STDERR.puts "Usage: #{$0} <token_name_prefix> <scopes_comma_separated>"
  STDERR.puts "Example: #{$0} 'automation-token' 'api,write_repository,read_repository'"
  exit 1
end

token_name_prefix = ARGV[0]
scopes_string = ARGV[1]
scopes = scopes_string.split(',').map(&:strip).map(&:to_sym)

user = User.find_by_username('root')
if user.nil?
  STDERR.puts 'ERROR: Root user not found!'
  exit 1
end

token = user.personal_access_tokens.create(
  name: "#{token_name_prefix}-#{Time.now.to_i}",
  scopes: scopes,
  expires_at: 365.days.from_now
)

if token.persisted?
  puts token.token
else
  STDERR.puts "Token creation failed: #{token.errors.full_messages.join(', ')}"
  exit 1
end
