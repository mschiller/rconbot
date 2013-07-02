#!/usr/bin/env ruby
STDOUT.puts "STARTING..."
require 'rconbot'
r = RconBot::Bot.new(:sv_password => '1', :maps => ['de_dust2', 'de_inferno', 'de_nuke', 'de_train'], :repeat => false, :passive_mode => true)
r.connect("115.124.106.17", 27016, 'tuesdaysgone', '/home/hlds/hlds_match_screen.log')
