#!/usr/bin/env ruby
# Script to fix common database sequences in GitLab
sequences = ['namespaces_id_seq', 'projects_id_seq', 'users_id_seq']
sequences.each do |seq|
  table_name = seq.gsub('_id_seq', '')
  max_id = ActiveRecord::Base.connection.execute("SELECT MAX(id) FROM #{table_name}").first['max'].to_i
  if max_id > 0
    ActiveRecord::Base.connection.execute("SELECT setval('#{seq}', #{max_id + 1}, false)")
    puts "Fixed #{seq} (set to #{max_id + 1})"
  end
end
puts 'Database sequences initialized'
