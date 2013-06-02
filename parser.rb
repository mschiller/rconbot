TIMESTAMP_REGEX = "L 0?[0-9]\/[0-9]{2}\/[0-9]{4} - [0-9]{2}:[0-9]{2}:[0-9]{2}: "

KILL_REGEX = /^#{TIMESTAMP_REGEX}\"(.+)<[0-9]+><(STEAM_[0-5]:[0-1]:[0-9]+)><(CT|TERRORIST)>\" killed \"(.+)<[0-9]+><(STEAM_[0-5]:[0-1]:[0-9]+)><(CT|TERRORIST)>\" with \"([a-z0-9]*)\"$/

MAP_REGEX = /changelevel/

ATTACK_REGEX = /^#{TIMESTAMP_REGEX}\"(.+)<[0-9]+><(STEAM_[0-5]:[0-1]:[0-9]+)><(CT|TERRORIST)>\" attacked \"(.+)<[0-9]+><(STEAM_[0-5]:[0-1]:[0-9]+)><(CT|TERRORIST)>\" with \"([a-z0-9]*)\" \(damage \"([0-9]*)\"\) \(damage_armor \"([0-9]*)\"\) \(health \"([0-9]*)\"\) \(armor \"([0-9]*)\"\)$/

LIVE_REGEX = /^#{TIMESTAMP_REGEX}Rcon: \"rcon [0-9]* \".*\" exec live.cfg" from \"[0-9\.:]*\"/

ROUNDEND_REGEX = /^#{TIMESTAMP_REGEX}Team \"(CT|TERRORIST)\" triggered \"(Target_Bombed|Target_Saved|Bomb_Defused|CTs_Win|Terrorists_Win)\" \(CT \"([0-9]{1,2})\"\) \(T "([0-9]{1,2})"\)/


module RConBot

  class Match
    attr_reader :max_rounds, :team_size
    attr_accessor :half
    
    def initialize
      @live = false
      @half = 1
      @team_size = 5
      @max_rounds = 15
    end
    
    def start
      @live = true
    end

    def stop
      @live = false
    end

    def live?
      @live
    end

    def map
      @map
    end
    
    def log_filename
      './logs/test.log'
    end
  end

  class Bot
    attr_accessor :match
    
    def connect
      @match = Match.new
      filename =  @match.log_filename
      f = File.open(filename, "r")
      f.seek(0, IO::SEEK_END)
      while true do
        select([f])
        line = f.gets
        process_line(line)
      end
    end
    
    def process_line(line)
      if m = LIVE_REGEX.match(line) or  m = /sv_restart/.match(line)
        puts "RESET!!!"
        # $redis.flushdb if $half == 1
        puts "LIVE!!! HALF => #{@match.half}"
        @match.start
      elsif @match.live? and m = KILL_REGEX.match(line)
        t, k_name, k_steam_id, k_team, v_name, v_steam_id, v_team, weapon = m.to_a
        
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
        points = ((@match.team_size - $alive[v_team]) + (@match.team_size - $alive[k_team]))
        
        case k_team
        when 'CT'
          pct = $redis.zincrby("skill.ct", points, k_steam_id)
        when 'TERRORIST'
          pt = $redis.zincrby("skill.t", points, k_steam_id)
        end
        
        # puts " -- #{t.split('-').last} #{k_name[0..4]} (#{k_team}) killed #{v_name[0..4]} (#{v_team})"
        
        $redis.zincrby("skill.#{weapon}", points, k_steam_id)
        $redis.zincrby("weapon.usage", 1, weapon)
        
        # PROBABLY BAD TECHNIQUE : update the score in (currently updating the ratio only)
        $redis.zadd("ratio", k.to_f/$redis.get("deaths:#{k_steam_id}").to_f, k_steam_id)
        $redis.zadd("ratio", $redis.get("kills:#{v_steam_id}").to_f/d.to_f, v_steam_id)
      # elsif $live and m = ATTACK_REGEX.match(line)
        #   a_name, a_steam_id, a_team, t_name, t_steam_id, t_team, weapon, damage, damage_armor, health, armor = m.to_a[1..-1]
        #   # raise l if a_steam_id == t_steam_id # can happen in self nade where damage
        #   puts " -- -- #{a_name[0..4]} -> #{t_name[0..4]} => #{health}"
        
        #   $healths[t_steam_id] = health
      elsif @match.live? and m = ROUNDEND_REGEX.match(line)
        t, winner, reason, ct_score, t_score = m.to_a
        puts "#{'*' * 25}  HALF #{@match.half}; ROUND #{ct_score.to_i+t_score.to_i}; CT: #{ct_score} T: #{t_score} #{'*' * 25}"
        if ct_score.to_i + t_score.to_i == @match.max_rounds
          @match.stop
          @match.half = 2
        end
        $alive['CT'] = @match.team_size
        $alive['TERRORIST'] = @match.team_size
        $healths = {}
      end
    end
    
  end
  
end


# rconbot + statcollector
`rm logs/test.log`
`touch logs/test.log`

require 'redis'
# require 'rcon'

# $rcon = RCon::Query::Original.new("schubert.com", '27015', 'tuesdaysgone')

$redis = Redis.new(:host => 'localhost', :port => '6379', :db => 6)
$redis.flushdb

puts "-" * 102


$alive = {'CT' => $team_size, 'TERRORIST' => $team_size}
$healths = {} # keeps track of player health, if does not exist 100 is assumed

def stats
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
end

