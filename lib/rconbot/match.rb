module RconBot
  class Match
    attr_reader :half_length, :team_size, :result, :team1, :team2, :stats, :map, :rcon_connection, :result, :spectator
    
    state_machine :initial => :wait_on_join do
      state :wait_on_join
      state :first_warm_up
      state :first_half
      state :second_warm_up
      state :second_half
      state :finished

      event :run do
        transition any => :wait_on_join
      end

      event :warm_up do
        transition :wait_on_join => :first_warm_up 
      end

      event :live do
        transition :first_warm_up => :first_half
        transition :second_warm_up => :second_half
      end

      event :halftime do
        transition :first_half => :second_warm_up
      end

      event :fulltime do
        transition :second_half => :finished
      end

      before_transition any => :wait_on_join, :do => :change_level
      after_transition any => :wait_on_join, :do => :wait_for_players
      
      before_transition :wait_on_join => :first_warm_up, :do => :exec_warmup_cfg
      after_transition :wait_on_join => :first_warm_up, :do => :wait_on_ready

      before_transition :first_half => :second_warm_up, :do => :exec_warmup_cfg
      after_transition :first_half => :second_warm_up, :do => :wait_on_ready
      
      before_transition :first_warm_up => :first_half, :do => :exec_live_cfg
      after_transition :first_warm_up => :first_half, :do => :process_match

      before_transition :second_warm_up => :second_half, :do => :exec_live_cfg
      after_transition :second_warm_up => :second_half, :do => :process_match

      before_transition :second_half => :finished, :do => :exec_pub_cfg
      after_transition :second_half => :finished, :do => :save_stats
    end
    
    def save_stats
      puts "SAVE_STATS"
      puts "ROUNDS COMPLETED => #{round}"
      puts "WINNER => #{@result.inspect}"
      puts "STATS => #{@stats.inspect}"
    end
    
    def initialize(team1, team2, map, rcon_connection, log_filename)
      @team_size = 5
      @half = 0
      @half_length = 15
      @team1 = team1
      @team2 = team2
      @spectator = Team.new('SPECTATOR') # this is not right!
      @rcon_connection = rcon_connection
      # monitor the logs 
      @logfile = File.open(log_filename, "r")
      @logfile.seek(0, IO::SEEK_END)
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

    def next_round
      team1.respawn
      team2.respawn
    end

    def halftime?
      round == @half_length
    end

    def fulltime?
      round == (@half_length * 2)
    end

    def won?
      return team1 if team1.score == @half_length + 1
      return team2 if team2.score == @half_length + 1
      return false
    end

    def round
      team1.score + team2.score
    end

    def wait_for_players
      puts "WAIT_FOR_PLAYERS"
      while true do
        select([@logfile])
        line = @logfile.gets
        check_client_connections(line)
        return if @team1.size == 1 or @team2.size == 1 # should be 5 and 5
      end
    end

    def wait_on_ready
      puts "WAIT_ON_READY"
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
                set_ready_state(r_team, true)
                puts "---------- R #{@team1.ready?} #{@team2.ready?}"
                return if @team1.ready? and @team2.ready?
              elsif m = NOT_READY_REGEX.match(line)
                t, r_name, r_steam_id, r_team = m.to_a
                set_ready_state(r_team, false)
                puts "---------- R #{@team1.ready?} #{@team2.ready?}"
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

    def process_match
      puts "PROCESS_MATCH"
      while true do 
        select([@logfile])
        line = @logfile.gets
        if m = LIVE_REGEX.match(line) or /sv_restart/.match(line) # 2nd condition could be removed but will it catch 100% of the times
          # flush half time stats because this might happen multiple times in some cases
          @stats = Stats.new(@team1, @team2)
        elsif @stats and m = KILL_REGEX.match(line)
          t, k_name, k_steam_id, k_team_type, v_name, v_steam_id, v_team_type, weapon = m.to_a

          k_team = self.send(k_team_type.downcase)
          v_team = self.send(v_team_type.downcase)

          raise line if k_steam_id == v_steam_id # can happen in suicide
          
          v_team.player_died(v_steam_id)
            
          # add aliases in case of change
          @stats.alias[k_steam_id][k_name] +=1
          
          # $redis.zincrby("alias:#{k_steam_id}", 1, k_name)
          # $redis.zincrby("alias:#{v_steam_id}", 1, v_name)
          
          # kills
          @stats.player[k_steam_id][:kills] += 1 unless k_team_type == v_team_type
          #k = $redis.incr("kills:#{k_steam_id}") #unless k_team == v_team # friendly fire
          # deaths
          @stats.player[v_steam_id][:deaths] += 1
          #d = $redis.incr("deaths:#{v_steam_id}") #unless
          
          # points for killer
          points = (k_team_type == v_team_type ? 0 : ((@team_size - k_team.alive_count) + (@team_size - v_team.alive_count)))
          @stats.player[:points][k_team_type] += points

          # case k_team
          # when 'CT'
          #   # $redis.zincrby("skill.ct", points, k_steam_id)
          # when 'TERRORIST'
          #   # $redis.zincrby("skill.t", points, k_steam_id)
          # end
          
          puts " -- #{k_name[0..4]} (#{k_team_type[0]}) killed #{v_name[0..4]} (#{v_team_type[0]}) with #{weapon} -- #{points} #{'wtf' if k_team_type == v_team_type} #{@alive.inspect}"
            
          # $redis.zincrby("skill.#{weapon}", points, k_steam_id)
          # $redis.zincrby("weapon.usage", 1, weapon)
          
          # PROBABLY BAD TECHNIQUE : update the score in (currently updating the ratio only)
          # $redis.zadd("ratio", k.to_f/# $redis.get("deaths:#{k_steam_id}").to_f, k_steam_id)
          # $redis.zadd("ratio", # $redis.get("kills:#{v_steam_id}").to_f/d.to_f, v_steam_id)
          # elsif $live and m = ATTACK_REGEX.match(line)
          #   a_name, a_steam_id, a_team, t_name, t_steam_id, t_team, weapon, damage, damage_armor, health, armor = m.to_a[1..-1]
          #   # raise l if a_steam_id == t_steam_id # can happen in self nade where damage
          #   puts " -- -- #{a_name[0..4]} -> #{t_name[0..4]} => #{health}"
        elsif @stats and m = ROUNDEND_REGEX.match(line)
          t, winner, reason, ct_score, terrorist_score = m.to_a

          ct.send("#{state}_score=", ct_score.to_i)
          terrorist.send("#{state}_score=", terrorist_score.to_i)

          # if first_half?
          #   ct.first_half_score = ct_score.to_i
          #   terrorist.first_half_score = terrorist_score.to_i
          # elsif second_half?
          #   ct.second_half_score = ct_score.to_i
          #   terrorist.second_half_score = terrorist_score.to_i
          # end
          
          puts "HALF => #{@half + 1}, ROUND => #{round}, MATCH ROUND => #{round}, SCORE => #{@team1.score}:#{@team2.score} [#{reason}]"
          
          return if halftime?
          if second_half?
            if w = won?
              @result = w
              return 
            elsif fulltime?
              return
            end
          end
          next_round
        end
      end
      puts "EXITING PROCESS_MATCH"
    end

    def ct
      return @team1 if first_half? or first_warm_up? or wait_on_join?
      return @team2 if second_half? or second_warm_up?
      return nil
    end

    def terrorist
      return @team2 if first_half? or first_warm_up? or wait_on_join?
      return @team1 if second_half? or second_warm_up?
      return nil
    end

    def set_ready_state(team_type, value)
      puts "SET_READY_STATE #{team_type} -> READY = #{value} #{state}"
      team = self.send(team_type.downcase)
      value ? team.is_ready : team.is_not_ready
    end

    def check_client_connections(line)
      # check connections disconnections
      if m = JOINED_TEAM_REGEX.match(line)
        t, j_name, j_steam_id, from_team_type, to_team_type = m.to_a
        if from_team_type
          from_team = self.send(from_team_type.downcase)
          from_team.is_not_ready
          from_team.remove_player(j_steam_id)
        end
        puts to_team_type.inspect
        to_team = self.send(to_team_type.downcase)
        puts to_team.inspect
        to_team.is_not_ready
        to_team.add_player(j_steam_id)
      elsif m = DISCONNECTED_REGEX.match(line)
        t, d_name, d_steam_id, from_team = m.to_a
        # reduce player reliability??? or should that be done from wait_on_ready (redis connection is slow)
        from_team = self.send(from_team_type)
        from_team.is_not_ready
        from_team.remove_player(d_steam_id)
      end
    end

  end
end
