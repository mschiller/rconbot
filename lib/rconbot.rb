# require 'redis'
require 'socket'
require 'timeout'
require 'set'
require 'state_machine'
require 'rconbot'
require 'rconbot/rcon_connection'
require 'rconbot/team'
require 'rconbot/stats'
require 'rconbot/match'
require 'rconbot/bot'

# $redis = Redis.new(:host => 'localhost', :port => '6379', :db => 6)
# $redis.flushdb

module RconBot

  TIMESTAMP_FORMAT = "L 0?[0-9]\/[0-9]{2}\/[0-9]{4} - [0-9]{2}:[0-9]{2}:[0-9]{2}:"
  
  TEAM_FORMAT = "(CT|TERRORIST)"  

  PLAYER_FORMAT = "\"(.+)<[0-9]+><(STEAM_[0-5]:[0-1]:[0-9]+)><#{TEAM_FORMAT}?>\""
  
  READY_REGEX = /^#{TIMESTAMP_FORMAT} #{PLAYER_FORMAT} say \"ready\"/

  NOT_READY_REGEX = /^#{TIMESTAMP_FORMAT} #{PLAYER_FORMAT} say \"not ready\"/
  
  CONNECTED_REGEX = /^#{TIMESTAMP_FORMAT} #{PLAYER_FORMAT} connected/

  ENTERED_REGEX = /^#{TIMESTAMP_FORMAT} #{PLAYER_FORMAT} entered the game/

  JOINED_TEAM_REGEX = /^#{TIMESTAMP_FORMAT} #{PLAYER_FORMAT} joined team \"#{TEAM_FORMAT}\"/

  DISCONNECTED_REGEX = /^#{TIMESTAMP_FORMAT} #{PLAYER_FORMAT} disconnected/
  
  KILL_REGEX = /^#{TIMESTAMP_FORMAT} #{PLAYER_FORMAT} killed #{PLAYER_FORMAT} with \"([a-z0-9]+)\"$/
  
  ATTACK_REGEX = /^#{TIMESTAMP_FORMAT} #{PLAYER_FORMAT} attacked #{PLAYER_FORMAT} with \"([a-z0-9]+)\" \(damage \"([0-9]+)\"\) \(damage_armor \"([0-9]+)\"\) \(health \"([0-9]+)\"\) \(armor \"([0-9]+)\"\)$/
  
  LIVE_REGEX = /^#{TIMESTAMP_FORMAT} Rcon: \"rcon [0-9]+ \".*\" exec live.cfg" from \"[0-9\.:]+\"/
  
  ROUNDEND_REGEX = /^#{TIMESTAMP_FORMAT} Team \"#{TEAM_FORMAT}\" triggered \"(Target_Bombed|Target_Saved|Bomb_Defused|CTs_Win|Terrorists_Win)\" \(CT \"([0-9]{1,2})\"\) \(T "([0-9]{1,2})"\)/

  SCORE_REGEX = /^#{TIMESTAMP_FORMAT} Team \"#{TEAM_FORMAT}\" scored \"([0-9]+)\" with \"([0-9]+)\" players/
  
  def self.stats
    puts '*' * 100
    
    puts "\nSKILL CT\n"
    puts # $redis.zrevrange("skill.ct", 0, -1, :with_scores => true).map{|x| {# $redis.zrevrange("alias:#{x[0]}",0,1)[0] => x[1] }}
    puts "SKILL T"
    puts # $redis.zrevrange("skill.t", 0, -1, :with_scores => true).map{|x| {# $redis.zrevrange("alias:#{x[0]}",0,1)[0] => x[1] }}
    
    puts '*' * 100
    
    puts "\nSKILL\n"
    # $redis.zunionstore("skill", ["skill.ct", "skill.t"])
    puts # $redis.zrevrange("skill", 0, -1, :with_scores => true).map{|x| {# $redis.zrevrange("alias:#{x[0]}",0,1)[0] => x[1] }}
    
    # puts '*' * 100
    
    # # $redis.zrevrange("weapon.usage", 0, -1).each do |weapon|
    #   puts "\nSKILL BY WEAPON #{weapon}\n"
    #   puts # $redis.zrevrange("skill.#{weapon}", 0, -1, :with_scores => true).map{|x| {# $redis.zrevrange("alias:#{x[0]}",0,-1)[0] => x[1] }}  
    # end
    
    # puts '*' * 100
    
    # puts "\nWEAPONS USED\n"
    # puts # $redis.zrevrange("weapon.usage", 0, -1, :with_scores => true).map{|x| {x[0] => x[1]}}
    
    puts '*' * 100
    
    puts "\nK:D RATIO\n"
    puts # $redis.zrevrange("ratio", 0, -1, :with_scores => true).map{|x| {# $redis.zrevrange("alias:#{x[0]}",0,1)[0] => x[1] }}
    
  end
  
end
