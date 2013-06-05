# require 'redis'
require 'timeout'
require 'socket'

`rm /tmp/test.log`
`touch /tmp/test.log`

# $redis = Redis.new(:host => 'localhost', :port => '6379', :db => 6)
# $redis.flushdb

TIMESTAMP_FORMAT = "L 0?[0-9]\/[0-9]{2}\/[0-9]{4} - [0-9]{2}:[0-9]{2}:[0-9]{2}:"

PLAYER_FORMAT = "\"(.+)<[0-9]+><(STEAM_[0-5]:[0-1]:[0-9]+)><(CT|TERRORIST)?>\""

READY_REGEX = /^#{TIMESTAMP_FORMAT} #{PLAYER_FORMAT} say \"ready\"/

CONNECTED_REGEX = /^#{TIMESTAMP_FORMAT} #{PLAYER_FORMAT} connected/

KILL_REGEX = /^#{TIMESTAMP_FORMAT} #{PLAYER_FORMAT} killed #{PLAYER_FORMAT} with \"([a-z0-9]*)\"$/

ATTACK_REGEX = /^#{TIMESTAMP_FORMAT} #{PLAYER_FORMAT} attacked #{PLAYER_FORMAT} with \"([a-z0-9]*)\" \(damage \"([0-9]*)\"\) \(damage_armor \"([0-9]*)\"\) \(health \"([0-9]*)\"\) \(armor \"([0-9]*)\"\)$/

LIVE_REGEX = /^#{TIMESTAMP_FORMAT} Rcon: \"rcon [0-9]* \".*\" exec live.cfg" from \"[0-9\.:]*\"/

ROUNDEND_REGEX = /^#{TIMESTAMP_FORMAT} Team \"(CT|TERRORIST)\" triggered \"(Target_Bombed|Target_Saved|Bomb_Defused|CTs_Win|Terrorists_Win)\" \(CT \"([0-9]{1,2})\"\) \(T "([0-9]{1,2})"\)/

module RconBot

  class RconConnection
    def initialize(host, port, password, type = 'l')
      @host = host
      @port = port
      @password = password
      @server_type = type
      connect
      get_challenge_id
    end
    
    def get_challenge_id
      response = socket_request("\xFF" * 4 + "challenge rcon" + "\x00", true)
      if challenge_id = /challenge rcon (\d+)/.match(response)
        @challenge_id = challenge_id[1]
      end
    end
    
    def command(request)
      socket_request("\xFF" * 4 + "rcon #{@challenge_id} \"#{@password}\" #{request}" + "\x00", true)
    end
    
    def connect
      @socket = UDPSocket.new
      @socket.connect(@host, @port)
    end

    def socket_request(request, challenge = false)
      puts "=> #{request.inspect}"
      @socket.print(request)
      retval = []
      loop do 
        select([@socket], nil, nil, 1)
        str = @socket.recv(65507)
        puts "<= #{str.inspect}"
        bytes = str.unpack("c*")
        puts str[(challenge ? 4 : 5)..-2]
        retval += bytes
        break
      end
      return retval.pack('c*')
    end
  end
  
  class Stats
    def initialize(team1, team2, map)
      @stats_key_prefix = "#{team1}:#{team2}:#{map}"
    end

    # type weapon, ct, t, or nil (overall)
    def skill(type = nil)
      
    end

    def kills(steam_id)
      
    end

    def deaths(steam_id)
      
    end

    def kd_ratio(steam_id)
      
    end
    
  end

  # match is a single game with 15 rounds each half, race to 16
  # a match is played on a single map
  class Match
    attr_reader :max_rounds, :team_size, :result, :team1, :team2, :stats
    attr_accessor :half, :score, :result, :status, :alive
    
    def initialize(team1 = '1', team2 = '2', map = 'dust2')
      @live = false
      @half = 0
      @team_size = 5
      @max_rounds = 2
      @team1 = team1
      @team2 = team2
      @score = [[0, 0], [0, 0]]
      @stats = Stats.new(team1, team2, map)
      @status = :wait_on_join # :wait_on_join :first_warmup :first_half :second_warmup :second_half :finished
      @alive = {'CT' => @team_size, 'TERRORIST' => @team_size}
    end

    def teams
      [@team1, @team2]
    end
    
    def start
      @live = true
      next_round
    end
    
    def next_round
      @alive = {'CT' => @team_size, 'TERRORIST' => @team_size}
    end

    def stop
      @live = false
    end
    
    def round
      @score.flatten.inject(0){|s, i| s += i; s}
    end

    def team_score(team)
      @score[0][team] + @score[1][team]
    end

    def live?
      @live
    end

    def map
      @map
    end

    def stats
      
    end
    
    def log_filename
      '/home/hlds/hlds_screen.log' # '/tmp/test.log'
    end

  end

  # can monitor N number of matches 
  class Bot
    attr_accessor :match
    attr_reader :rcon_connection # must not be there cuz private
    
    # options :team1 :team2 :maps :timelimit
    def connect(host, port, password, options = {})
      options[:team1] ||= 'team1'
      options[:team2] ||= 'team2'
      options[:maps] ||= ['de_dust2']
      options[:sv_password] ||= 'testing'
      
      @rcon_connection = RconConnection.new(host, port, password)
      @rcon_connection.command("sv_password \"#{options[:sv_password]}\"")

      options[:maps].each do |map|
        @match = Match.new(options[:team1], options[:team2], map)
        # @rcon_connection.command("kick all 'Sorry, scheduled match to take place. Visit www.fragg.in to participate.'")
        @rcon_connection.command("changelevel #{map}")
        filename =  @match.log_filename
        f = File.open(filename, "r")
        f.seek(0, IO::SEEK_END)
        @match.status = wait_on_join(f)
        @match.status = wait_on_ready(f, :first_half)
        @match.status = process_match(f)
        @match.status = wait_on_ready(f, :second_half)
        @match.status = process_match(f)
      end
    end

    def wait_on_join(f)
      while true do
        select([f])
        line = f.gets
        #print '.'
        #sleep(5)
        if line =~ CONNECTED_REGEX
          puts "CONNECTED"
          # @rcon_connection.command("say WARMUP GUYS!!!")
          return :first_warmup 
        end
      end
    end

    def wait_on_ready(f, status)
      begin
        Timeout::timeout(5) do
          while true do
            select([f])
            line = f.gets
            #print '.'
            #sleep(5)
            if line =~ READY_REGEX
              puts "ALL READY"
              @rcon_connection.command("exec live.cfg")
              return status
            end
          end
        end
      rescue => e 
        @rcon_connection.command("say say ready when ready")
        # FIXME: can cause a stack level to deep error!!!
        wait_on_ready(f, status)
      end
    end

    def process_match(f)
      while true do 
        select([f])
        line = f.gets
        if m = LIVE_REGEX.match(line) or m = /sv_restart/.match(line)
          puts "LIVE!!!"
          @match.start
        elsif @match.live? and m = KILL_REGEX.match(line)
          t, k_name, k_steam_id, k_team, v_name, v_steam_id, v_team, weapon = m.to_a
          raise l if k_steam_id == v_steam_id # can happen in suicide
          
          @match.alive[v_team] -= 1
            
          # add aliases in case of change
          # $redis.zincrby("alias:#{k_steam_id}", 1, k_name)
          # $redis.zincrby("alias:#{v_steam_id}", 1, v_name)
          
          # kills
          #k = $redis.incr("kills:#{k_steam_id}") #unless k_team == v_team # friendly fire
          # deaths
          #d = $redis.incr("deaths:#{v_steam_id}") #unless
          
          # points for killer
          points = ((@match.team_size - @match.alive[k_team]) + (@match.team_size - @match.alive[v_team]))
          points = 0 if k_team == v_team # friendly fire
          
          case k_team
          when 'CT'
            # $redis.zincrby("skill.ct", points, k_steam_id)
          when 'TERRORIST'
            # $redis.zincrby("skill.t", points, k_steam_id)
          end
          
          puts " -- #{k_name[0..4]} (#{k_team[0]}) killed #{v_name[0..4]} (#{v_team[0]}) with #{weapon} -- #{points} #{'wtf' if k_team == v_team} #{@match.alive.inspect}"
            
          # $redis.zincrby("skill.#{weapon}", points, k_steam_id)
          # $redis.zincrby("weapon.usage", 1, weapon)
          
          # PROBABLY BAD TECHNIQUE : update the score in (currently updating the ratio only)
          # $redis.zadd("ratio", k.to_f/# $redis.get("deaths:#{k_steam_id}").to_f, k_steam_id)
          # $redis.zadd("ratio", # $redis.get("kills:#{v_steam_id}").to_f/d.to_f, v_steam_id)
          # elsif $live and m = ATTACK_REGEX.match(line)
          #   a_name, a_steam_id, a_team, t_name, t_steam_id, t_team, weapon, damage, damage_armor, health, armor = m.to_a[1..-1]
          #   # raise l if a_steam_id == t_steam_id # can happen in self nade where damage
          #   puts " -- -- #{a_name[0..4]} -> #{t_name[0..4]} => #{health}"
        elsif @match.live? and m = ROUNDEND_REGEX.match(line)
          t, winner, reason, ct_score, t_score = m.to_a
          
          if @match.half == 0
            @match.score[@match.half][0] = ct_score.to_i
            @match.score[@match.half][1] = t_score.to_i
          elsif @match.half == 1
            @match.score[@match.half][1] = ct_score.to_i
            @match.score[@match.half][0] = t_score.to_i
          end
          
          puts "HALF #{@match.half + 1}, ROUND #{@match.round}, SCORE #{@match.team1} => #{@match.score[@match.half][0]}, #{@match.team2} => #{@match.score[@match.half][1]} #{reason}"
          
          if @match.round == @match.max_rounds
            @match.stop
            @match.half += 1
            return :second_warmup
          else
            if @match.team_score(0) == 16 
              @match.stop
              @match.result = 0 # team1 (CT first T second)
            elsif @match.team_score(1) == 16
              @match.stop 
              @match.result = 1 # team2
            elsif @match.round == @match.max_rounds * 2
              @match.stop
              @match.result = -1 # Draw
            end

            if @match.result 
              if @match.result != -1
                puts "RESULT => DRAW" 
              else
                puts "RESULT => #{@match.teams[@match.result]}" 
              end
              return :finished
            end
          end
          @match.next_round
        end
      end
    end
  end
end
  
def stats
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

