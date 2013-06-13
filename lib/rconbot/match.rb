module RconBot
  class Match
    attr_reader :half_length, :team_size, :result, :team1, :team2, :stats, :half, :map, :rcon_connection
    attr_accessor :score, :result
    
    state_machine :initial => :wait_on_join do
      state :first_warm_up
      state :first_half
      state :second_warm_up
      state :second_half
      state :finished
      
      before_transition any - :wait_on_join => :wait_on_join, :do => :change_level
      before_transition :wait_on_join => :first_warm_up, :do => :exec_warmup_cfg
      
      event :wait_for_players do
        transition :connected => :wait_on_join
      end
      event :first_warm_up do
        transition :wait_on_join => :first_warm_up, :second_half => :second_warm_up
      end
      before_transition :first_warm_up => :first_half, :second_warm_up => :second_half, :do => :exec_live_cfg
    end
    
    def initialize(team1, team2, map, rcon_connection, log_filename)
      @live = false
      @team_size = 5
      @half = 0
      @half_length = 15
      @team1 = team1
      @team2 = team2
      @score = [[0, 0], [0, 0]]
      @rcon_connection = rcon_connection
      # monitor the logs 
      @logfile = File.open(log_filename, "r")
      @logfile.seek(0, IO::SEEK_END)
      @alive = {'CT' => @team_size, 'TERRORIST' => @team_size}
      super()
    end
    
    def exec_warmup_cfg
      puts "EXEC_WARMUP_CFG"
      @rcon_connection.command("exec warmup.cfg")
    end

    def exec_pub_cfg
      puts "EXEC_PUB_CFG"
      @rcon_connection.command("exec pub.cfg")
    end

    def exec_live_cfg
      puts "EXEC_LIVE_CFG"
      @rcon_connection.command("exec live.cfg")
    end
    
    def change_level
      puts "CHANGE_LEVEL"
      @rcon_connection.command("changelevel #{@map}") if @map
    end

    def start
      puts "STARTED"
      @status += 1
      next_round
    end

    # def live
    #   puts "LIVE"
    #   @live = true
    # end

    def stop
      @live = false
    end
    
    def next_round
      @alive = {'CT' => @team_size, 'TERRORIST' => @team_size}
    end

    def end_half
      stop
      @half += 1
      @status += 1
    end

    def end_match(result)
      stop
      @result = result
      puts "RESULT => #{(@result == -1 ? "DRAW" : teams[@result])}"
      @status += 1
    end

    def current_status
      STATUS[@status]
    end

    def halftime?
      round == @half_length
    end

    def fulltime?
      round == (@half_length * 2)
    end

    def won?
      return 0 if team_score(0) == @half_length + 1
      return 1 if team_score(1) == @half_length + 1
      return false
    end

    def teams
      [@team1, @team2]
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

    def wait_on_join
      puts "WAIT_FOR_PLAYERS"
      while true do
        select([@logfile])
        line = @logfile.gets
        check_client_connections(line)
        # sleep(1);puts "#{state}"
        return first_warm_up if @team1.size == 1 or @team2.size == 1
      end
      
    end

    def warm_up
      puts "WARM_UP"
      ttl = 100 # seconds
      msg_interval = 5 # seconds
      (ttl/msg_interval).times do |c|
        begin
          Timeout::timeout(msg_interval) do
            while true do
              select([@logfile])
              line = @logfile.gets
              check_client_connections(line)
              # should the next one be some kinda elsif because of overhead
              if m = READY_REGEX.match(line)
                t, r_name, r_steam_id, r_team = m.to_a
                set_ready_state(r_team)
                puts "---------- R #{@team1.ready?} #{@team2.ready?}"
                if @team1.ready? or @team2.ready?
                  return first_half if first_warm_up
                end
              end
            end
          end
        rescue Timeout::Error
          @rcon_connection.command("say RconBot is at your service...")
          @rcon_connection.command("say Team1 [C]: #{@team1.players.length} players [#{@team1.ready? ? 'READY' : 'NOT READY'}]")
          @rcon_connection.command("say Team2 [T]: #{@team2.players.length} players [#{@team2.ready? ? 'READY' : 'NOT READY'}]")
          @rcon_connection.command("say say ready when ready [time left: #{ttl - (c * msg_interval)} seconds]")
        end
      end
    end

    def live
      puts "LIVE"
      while true do 
        select([@logfile])
        line = @logfile.gets
        # if m = LIVE_REGEX.match(line) or /sv_restart/.match(line) # 2nd condition could be removed but will it catch 100% of the times
        #   # flush half time stats because this might happen multiple times in some cases
        #   @stats = true
        # elsif @stats and m = KILL_REGEX.match(line)
        #   t, k_name, k_steam_id, k_team, v_name, v_steam_id, v_team, weapon = m.to_a
        #   raise l if k_steam_id == v_steam_id # can happen in suicide
          
        #   @alive[v_team] -= 1
            
        #   # add aliases in case of change
        #   # $redis.zincrby("alias:#{k_steam_id}", 1, k_name)
        #   # $redis.zincrby("alias:#{v_steam_id}", 1, v_name)
          
        #   # kills
        #   #k = $redis.incr("kills:#{k_steam_id}") #unless k_team == v_team # friendly fire
        #   # deaths
        #   #d = $redis.incr("deaths:#{v_steam_id}") #unless
          
        #   # points for killer
        #   points = ((@team_size - @alive[k_team]) + (@team_size - @alive[v_team]))
        #   points = 0 if k_team == v_team # friendly fire
          
        #   case k_team
        #   when 'CT'
        #     # $redis.zincrby("skill.ct", points, k_steam_id)
        #   when 'TERRORIST'
        #     # $redis.zincrby("skill.t", points, k_steam_id)
        #   end
          
        #   puts " -- #{k_name[0..4]} (#{k_team[0]}) killed #{v_name[0..4]} (#{v_team[0]}) with #{weapon} -- #{points} #{'wtf' if k_team == v_team} #{@alive.inspect}"
            
        #   # $redis.zincrby("skill.#{weapon}", points, k_steam_id)
        #   # $redis.zincrby("weapon.usage", 1, weapon)
          
        #   # PROBABLY BAD TECHNIQUE : update the score in (currently updating the ratio only)
        #   # $redis.zadd("ratio", k.to_f/# $redis.get("deaths:#{k_steam_id}").to_f, k_steam_id)
        #   # $redis.zadd("ratio", # $redis.get("kills:#{v_steam_id}").to_f/d.to_f, v_steam_id)
        #   # elsif $live and m = ATTACK_REGEX.match(line)
        #   #   a_name, a_steam_id, a_team, t_name, t_steam_id, t_team, weapon, damage, damage_armor, health, armor = m.to_a[1..-1]
        #   #   # raise l if a_steam_id == t_steam_id # can happen in self nade where damage
        #   #   puts " -- -- #{a_name[0..4]} -> #{t_name[0..4]} => #{health}"
        # elsif @stats and m = ROUNDEND_REGEX.match(line)
        #   t, winner, reason, ct_score, t_score = m.to_a
          
        #   if @half == 0
        #     @score[@half][0] = ct_score.to_i
        #     @score[@half][1] = t_score.to_i
        #   elsif @half == 1
        #     @score[@half][1] = ct_score.to_i
        #     @score[@half][0] = t_score.to_i
        #   end
          
        #   puts "HALF #{@half + 1}, ROUND #{@round}, SCORE #{@team1} => #{@score[@half][0]}, #{@team2} => #{@score[@half][1]} #{reason}"

        #   # new
        #   if @halftime?
        #     @rcon_connection.command("exec warmup.cfg")
        #     return end_half
        #   else
        #     if w = @won?  
        #       @rcon_connection.command("exec server.cfg")
        #       return end_match(w)
        #     elsif @fulltime?
        #       @rcon_connection.command("exec server.cfg")
        #       return end_match(-1)
        #     end
        #   end
        #   @next_round
        # end
      end
    end

    def set_ready_state(team)
      puts "SRS #{team} #{first_warm_up?} #{second_warm_up?}"
      @team1.is_ready if (first_warm_up? and team == 'CT') or (second_warm_up? and team == 'TERRORIST')
      @team2.is_ready if (first_warm_up? and team == 'TERRORIST') or (second_warm_up? and team == 'CT')
      puts @team1.ready?
      puts @team2.ready?
    end

    def check_client_connections(line)
      # check connections disconnections
      if m = JOINED_TEAM_REGEX.match(line)
        t, j_name, j_steam_id, from_team, to_team = m.to_a
        case to_team
        when 'CT'
          @team1.add_player(j_steam_id)
        when 'TERRORIST'
          @team2.add_player(j_steam_id)
        end
      elsif m = DISCONNECTED_REGEX.match(line)
        t, d_name, d_steam_id, from_team = m.to_a
        # reduce player reliability??? or should that be done from wait_on_ready (redis connection is slow)
        case from_team
        when 'CT'
          @team1.remove_player(d_steam_id)
        when 'TERRORIST'
          @team2.remote_player(d_steam_id)
        end
      end
    end

  end
end
