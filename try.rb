#!/usr/bin/env ruby
STDOUT.puts "STARTING..."
require 'rconbot'
r = RconBot::Bot.new
r.connect("115.124.106.17", 27015, 'tuesdaysgone', :maps => ['de_dust2', 'de_inferno', 'de_nuke', 'de_train', :password => ""])
