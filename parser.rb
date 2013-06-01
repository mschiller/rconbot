# rconbot + statcollector

require 'redis'

# i need this
def watch_for(file, pattern)
  f = File.open(file,"r")
  #f.seek(0,IO::SEEK_END)
  while true do
    select([f])
    line = f.gets
    puts "Found it! #{line}" if line=~pattern or line =~ /ERROR/
  end
end

$redis = Redis.new(:host => 'localhost', :port => '6379', :db => 6)

LINES = File.readlines('logs/L0528003.log').to_a

TIMESTAMP_REGEX = "L 0?[0-9]\/[0-9]{2}\/[0-9]{4} - [0-9]{2}:[0-9]{2}:[0-9]{2}: "

KILL_REGEX = /^#{TIMESTAMP_REGEX}\"(.+)<[0-9]+><(STEAM_[0-5]:[0-1]:[0-9]+)><(CT|TERRORIST)>\" killed \"(.+)<[0-9]+><(STEAM_[0-5]:[0-1]:[0-9]+)><(CT|TERRORIST)>\" with \"([a-z0-9]*)\"$/

ATTACK_REGEX = /^#{TIMESTAMP_REGEX}\"(.+)<[0-9]+><(STEAM_[0-5]:[0-1]:[0-9]+)><(CT|TERRORIST)>\" attacked \"(.+)<[0-9]+><(STEAM_[0-5]:[0-1]:[0-9]+)><(CT|TERRORIST)>\" with \"([a-z0-9]*)\" \(damage \"([0-9]*)\"\) \(damage_armor \"([0-9]*)\"\) \(health \"([0-9]*)\"\) \(armor \"([0-9]*)\"\)$/

LIVE_REGEX = /^#{TIMESTAMP_REGEX}Rcon: \"rcon [0-9]* \".*\" exec live.cfg" from \"[0-9\.:]*\"/

ROUNDEND_REGEX = /^#{TIMESTAMP_REGEX}Team \"(CT|TERRORIST)\" triggered \"(Target_Bombed|Bomb_Defused|CTs_Win|Terrorists_Win)\" \(CT \"([0-9]{1,2})\"\) \(T "([0-9]{1,2})"\)/

puts "-" * 102

$live = false
$half = 1
$max_rounds = 15

$alive = {'CT' => 5, 'TERRORIST' => 5}
$healths = {} # keeps track of player health, if does not exist 100 is assumed
LINES.select do |l| 
  if m = LIVE_REGEX.match(l)
    puts "LIVE!!! HALF => #{$half}"
    $redis.flushdb if $half == 1
    $live = true
  elsif $live and m = KILL_REGEX.match(l)
    k_name, k_steam_id, k_team, v_name, v_steam_id, v_team, weapon = m.to_a[1..-1]

    raise l if k_steam_id == v_steam_id # can happen in suicide

    $alive[v_team] -= 1
    $healths[v_steam_id] ||= 100

    # add aliases in case of change
    $redis.zincrby("alias:#{k_steam_id}", 1, k_name)
    $redis.zincrby("alias:#{v_steam_id}", 1, v_name)

    # kills
    k = $redis.incr("kills:#{k_steam_id}")
    # deaths
    d = $redis.incr("deaths:#{v_steam_id}")
    
    # points for killer
    points = ((5 - $alive[v_team]) + (5 - $alive[k_team]))

    case k_team
    when 'CT'
      pct = $redis.zincrby("skill.ct", points, k_steam_id)
    when 'TERRORIST'
      pt = $redis.zincrby("skill.t", points, k_steam_id)
    end
    
    puts " -- #{k_name[0..4]} (#{k_team}) killed #{v_name[0..4]} (#{v_team}) -- #{weapon} -- POINTS => #{points}" # but HP was #{$healths[v_steam_id] || '100'}"

    $redis.zincrby("skill.#{weapon}", points, k_steam_id)
    $redis.zincrby("weapon.usage", 1, weapon)

    # PROBABLY BAD TECHNIQUE : update the score in (currently updating the ratio only)
    $redis.zadd("ratio", k.to_f/$redis.get("deaths:#{k_steam_id}").to_f, k_steam_id)
    $redis.zadd("ratio", $redis.get("kills:#{v_steam_id}").to_f/d.to_f, v_steam_id)
  elsif $live and m = ATTACK_REGEX.match(l)
  #   a_name, a_steam_id, a_team, t_name, t_steam_id, t_team, weapon, damage, damage_armor, health, armor = m.to_a[1..-1]
  #   # raise l if a_steam_id == t_steam_id # can happen in self nade where damage
  #   puts " -- -- #{a_name[0..4]} -> #{t_name[0..4]} => #{health}"

  #   $healths[t_steam_id] = health
  elsif $live and m = ROUNDEND_REGEX.match(l)
    t, winner, reason, ct_score, t_score = m.to_a
    puts "#{'*' * 25}  HALF #{$half}; ROUND #{ct_score.to_i+t_score.to_i}; CT: #{ct_score} T: #{t_score} #{'*' * 25}"
    if ct_score.to_i + t_score.to_i == $max_rounds
      $half = 2
      $live = false
    end
    $alive['CT'] = 5
    $alive['TERRORIST'] = 5
    $healths = {}
  end
end
puts '*' * 100

puts "\nSKILL CT\n"
puts $redis.zrevrange("skill.ct", 0, -1, :with_scores => true).map{|x| {$redis.zrevrange("alias:#{x[0]}",0,-1)[0] => x[1] }}
puts "SKILL T"
puts $redis.zrevrange("skill.t", 0, -1, :with_scores => true).map{|x| {$redis.zrevrange("alias:#{x[0]}",0,-1)[0] => x[1] }}

puts '*' * 100

puts "\nSKILL\n"
$redis.zunionstore("skill", ["skill.ct", "skill.t"])
puts $redis.zrevrange("skill", 0, -1, :with_scores => true).map{|x| {$redis.zrevrange("alias:#{x[0]}",0,-1)[0] => x[1] }}

puts '*' * 100

$redis.zrevrange("weapon.usage", 0, -1).each do |weapon|
  puts "\nSKILL BY WEAPON #{weapon}\n"
  puts $redis.zrevrange("skill.#{weapon}", 0, -1, :with_scores => true).map{|x| {$redis.zrevrange("alias:#{x[0]}",0,-1)[0] => x[1] }}  
end

puts '*' * 100

puts "\nK:D RATIO\n"
puts $redis.zrevrange("ratio", 0, -1, :with_scores => true).map{|x| {$redis.zrevrange("alias:#{x[0]}",0,-1)[0] => x[1] }}

puts '*' * 100

puts "\nWEAPONS USED\n"
puts $redis.zrevrange("weapon.usage", 0, -1, :with_scores => true).map{|x| {x[0] => x[1]}}


