module RconBot
  
  WEAPON_COST = {'ak47' => 2, 'm4a1' => 2, 'usp' => 4, 'glock' => '5', 'deagle' => 3, 'famas' => 3, 'galil' => 3, 'awp' => 1}
  
  require 'redis'
  $redis_connection = Redis.new(:db => 1)

  class Match
    attr_reader :half_length, :team_size, :result, :team1, :team2, :stats, :aliases, :map, :result
    attr_accessor :spectator, :live
    
    state_machine :initial => :wait_on_join do
      state :wait_on_join
      state :first_warm_up
      state :first_half
      state :second_warm_up
      state :second_half
      state :finished

      event :setup do
        transition any => :wait_on_join
      end

      event :warm_up do
        transition :wait_on_join => :first_warm_up
        transition :first_half => :second_warm_up
      end

      event :start do
        # active mode (with warmup time)
        transition :first_warm_up => :first_half
        transition :second_warm_up => :second_half

        # passive mode (manual rcon)
        transition :wait_on_join => :first_half, :if => :passive_mode
        transition :first_half => :second_half, :if => :passive_mode
      end

      event :fulltime do
        transition :second_half => :finished
      end

      event :abandon do 
        transition any => :finished
      end

      # around_transition :benchmark

      before_transition any => :wait_on_join, :do => :change_level
      after_transition any => :wait_on_join, :do => :wait_for_players
      
      before_transition :wait_on_join => :first_warm_up, :do => :exec_warmup_cfg
      after_transition :wait_on_join => :first_warm_up, :do => :wait_on_ready

      before_transition :first_half => :second_warm_up, :do => :exec_warmup_cfg
      after_transition :first_half => :second_warm_up, :do => :wait_on_ready
      
      before_transition :first_warm_up => :first_half, :do => :exec_live_cfg
      after_transition any => :first_half, :do => :process_match

      before_transition :second_warm_up => :second_half, :do => :exec_live_cfg
      after_transition any => :second_half, :do => :process_match

      before_transition :second_half => :finished, :do => :exec_pub_cfg
      after_transition :second_half => :finished, :do => :save_stats

    end

    def passive_mode
      @bot.passive_mode
    end

    def save_stats
      puts "SAVE_STATS"
      match_id = 1
      [:first_half, :second_half].each do |half|
        # kills, deaths, points
        @stats[half].each do |stat|
          killer, k_name, victim, v_name, weapon = stat

          $redis_connection.zincrby("ALIAS:#{killer}", 1, k_name)
          $redis_connection.zincrby("ALIAS:#{victim}", 1, v_name)

          $redis_connection.incrby("K:#{match_id}:#{killer}", 1)
          $redis_connection.incrby("D:#{match_id}:#{victim}", 1)
          
          # score updated using ELO formula
          # http://en.wikipedia.org/wiki/Elo_rating_system
          killer_old_score = $redis_connection.zscore("S:#{match_id}", killer) || 1000
          victim_old_score = $redis_connection.zscore("S:#{match_id}", victim) || 1000

          killer_expected_score = 1.0 / ( 1.0 + ( 10.0 ** ((victim_old_score.to_f - killer_old_score.to_f) / 400.0) ) )
          victim_expected_score = 1.0 / ( 1.0 + ( 10.0 ** ((killer_old_score.to_f - victim_old_score.to_f) / 400.0) ) )

          weapon_weight = 1
          
          killer_delta = weapon_weight.to_f * (1.0 - killer_expected_score)
          victim_delta = weapon_weight.to_f * (0 - victim_expected_score)

          puts "#{k_name} (+#{killer_delta}) -> #{v_name} (#{victim_delta})"

          $redis_connection.zadd("S:#{match_id}", killer_old_score + killer_delta, killer)
          $redis_connection.zadd("S:#{match_id}", victim_old_score + victim_delta, victim)
        end
        # round info
        @rounds[half].each do |player, count|
          $redis_connection.incrby("R:#{match_id}:#{player}", count)
        end
      end
    
      puts "ROUNDS COMPLETED => #{round}"
      puts "WINNER => #{@result.inspect}"
      puts "STATS => #{@stats.inspect}"
      puts "ROUNDS => #{@rounds.inspect}"
    end
    
    def initialize(bot, team1, team2, map)
      @bot = bot
      @half = 0
      @half_length = 15

      @team1 = Team.new(team1)
      @team2 = Team.new(team2)
      @spectator = Team.new('SPECTATOR') 

      @map = map

      @stats = {}
      @aliases = {}
      @rounds = {}

      # monitor the logs 
      @log_file = File.open(@bot.log_filename, "r")
      @log_file.seek(0, IO::SEEK_END)
      super()
    end
    
    def exec_warmup_cfg
      puts "EXEC_WARMUP_CFG"
      @bot.rcon_connection.command("exec warmup.cfg")
    end

    def exec_pub_cfg
      puts "EXEC_PUB_CFG"
      @bot.rcon_connection.command("exec pub.cfg")
    end

    def exec_live_cfg
      puts "EXEC_LIVE_CFG"
      @bot.rcon_connection.command("exec live.cfg")
    end
    
    def change_level
      puts "CHANGE_LEVEL #{@map}"
      @bot.rcon_connection.command("changelevel #{@map}") if @map
    end

    def reset_teams
      puts "RESET_TEAMS"
      team1.respawn
      team2.respawn
    end

    def switch_teams
      puts "SWITCH_TEAMS"
      k = team1.players
      team1.players = team2.players
      team2.players = k
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

    def last_round?
      round == @half_length - 1 or round == (@half_length * 2 - 1)
    end

    def wait_for_players
      puts "WAIT_FOR_PLAYERS"
      while true do
        select([@log_file])
        line = @log_file.gets
        update_teams(line)
        return if team1.size == 1 or team2.size == 1 # should be 5 and 5
      end
    end

    def wait_on_ready
      puts "WAIT_ON_READY"
      ttl = 60 # seconds
      msg_interval = 5 # seconds
      (ttl/msg_interval).times do |c|
        begin
          Timeout::timeout(msg_interval) do
            while true do
              select([@log_file])
              line = @log_file.gets
              update_teams(line)
              # should the next one be some kinda elsif because of overhead
              if m = READY_REGEX.match(line)
                t, r_name, r_steam_id, r_team = m.to_a
                set_ready_state(r_team, true)
                puts "---------- R #{team1.ready?} #{team2.ready?}"
                return if team1.ready? and team2.ready?
              elsif m = NOT_READY_REGEX.match(line)
                t, r_name, r_steam_id, r_team = m.to_a
                set_ready_state(r_team, false)
                puts "---------- R #{team1.ready?} #{team2.ready?}"
              end
            end
          end
        rescue Timeout::Error
          @bot.rcon_connection.command("say RconBot is at your service...")
          @bot.rcon_connection.command("say Team1 [C]: #{team1.players.length} players [#{team1.ready? ? 'READY' : 'NOT READY'}]")
          @bot.rcon_connection.command("say Team2 [T]: #{team2.players.length} players [#{team2.ready? ? 'READY' : 'NOT READY'}]")
          @bot.rcon_connection.command("say say ready when ready [time left: #{ttl - (c * msg_interval)} seconds]")
        end
      end

    end

    def process_match
      puts "PROCESS_MATCH"
      while true do 
        select([@log_file])
        line = @log_file.gets
        update_teams(line)
        if m = LIVE_REGEX.match(line) or /sv_restart/.match(line) # 2nd condition could be removed but will it catch 100% of the times
          puts "-" * 20 + " LIVE " + "-" * 20
          @live = true
          @stats[state_name] = []
          @rounds[state_name] = {}
          @aliases[state_name] = {}
          reset_teams
        elsif @live and m = KILL_REGEX.match(line)
          t, k_name, k_steam_id, k_team_type, v_name, v_steam_id, v_team_type, weapon = m.to_a

          k_team = self.send(k_team_type.downcase)
          v_team = self.send(v_team_type.downcase)

          raise line if k_steam_id == v_steam_id # can happen in suicide
          
          v_team.player_died(v_steam_id)
            
          # add aliases in case of changes
          
          # kills
          
          # round recorder
          @stats[state_name] << [k_steam_id, k_name, v_steam_id, v_name, weapon]

          # team skills

          # case k_team
          # when 'CT'
          #   # $redis.zincrby("skill.ct", points, k_steam_id)
          # when 'TERRORIST'
          #   # $redis.zincrby("skill.t", points, k_steam_id)
          # end
          
          puts " -- #{t.split(' ')[3]} #{k_name[0..5]} (#{k_team_type[0]}) killed #{v_name[0..5]} (#{v_team_type[0]}) with #{weapon} -- #{'WTF' if k_team_type == v_team_type}"
            
          # $redis.zincrby("skill.#{weapon}", points, k_steam_id)
          # $redis.zincrby("weapon.usage", 1, weapon)

          # elsif $live and m = ATTACK_REGEX.match(line)
          #   a_name, a_steam_id, a_team, t_name, t_steam_id, t_team, weapon, damage, damage_armor, health, armor = m.to_a[1..-1]
          #   # raise l if a_steam_id == t_steam_id # can happen in self nade where damage
          #   puts " -- -- #{a_name[0..4]} -> #{t_name[0..4]} => #{health}"
        elsif @live and m = ROUNDEND_REGEX.match(line)
          t, winner, reason, ct_score, terrorist_score = m.to_a

          # update score
          ct.send("#{state}_score=", ct_score.to_i)
          terrorist.send("#{state}_score=", terrorist_score.to_i)

          #player round counter
          (team1.players | team2.players).each do |player|
            @rounds[state_name][player] ||= 0
            @rounds[state_name][player] += 1
          end
          
          puts "ROUND => #{round}, SCORE => #{team1.score}:#{team2.score} [#{reason}], LINEUP => [#{team1.players.size} v #{team2.players.size} (#{@spectator.players.size})]    "
          
          if halftime?
            @live = false
            switch_teams
            return
          end
          if second_half?
            if w = won?
              @live = false
              @result = w
              return 
            elsif fulltime?
              @live = false
              return
            end
          end
          reset_teams
        end
      end
      puts "EXITING PROCESS_MATCH"
    end

    def ct
      return team1 if first_half? or first_warm_up? or wait_on_join?
      return team2 if second_half? or second_warm_up?
      return nil
    end

    def terrorist
      return team2 if first_half? or first_warm_up? or wait_on_join?
      return team1 if second_half? or second_warm_up?
      return nil
    end

    def set_ready_state(team_type, value)
      puts "SET_READY_STATE #{team_type} -> READY = #{value} #{state}"
      team = self.send(team_type.downcase)
      value ? team.is_ready : team.is_not_ready
    end

    def update_teams(line)
      # players joining leaving a team and team being ready or not-ready is updated here
      
      if m = JOINED_TEAM_REGEX.match(line)
        t, j_name, j_steam_id, from_team_type, to_team_type = m.to_a

        if from_team_type
          if @live and from_team_type != 'SPECTATOR' and to_team_type != 'SPECTATOR'
            # this guy is switching in between the match from T <-> CT
            # we must kick him or warn him unless he is dead and this is the last round (but our counts are wrong)
            @bot.rcon_connection.command("say #{state} #{@live} RconBot has kicked #{j_name}. Switching teams in between a round is strictly prohibited!") # unless last_round?
            @bot.rcon_connection.command("kick #{j_steam_id} \"Switching teams in between a round is strictly prohibited. Please reconnect!\"")
          end
          from_team = self.send(from_team_type.downcase)
          from_team.is_not_ready
          from_team.remove_player(j_steam_id)
        end
        to_team = self.send(to_team_type.downcase)
        to_team.is_not_ready
        to_team.add_player(j_steam_id)
        puts " -- -- >> #{j_steam_id} (#{from_team_type[0..0] rescue 'X'} -> #{to_team_type[0..0] rescue 'X'}), LINEUP => [#{team1.players.size} v #{team2.players.size} (#{@spectator.players.size})]"
      elsif m = DISCONNECTED_REGEX.match(line)
        t, d_name, d_steam_id, from_team_type = m.to_a
        # reduce player reliability??? or should that be done from wait_on_ready (redis connection is slow)
        if from_team_type
          from_team = self.send(from_team_type.downcase)
          from_team.is_not_ready
          from_team.remove_player(d_steam_id)
        end
        puts " -- -- << #{d_steam_id} (#{from_team_type[0..0] rescue 'X'} -> #{to_team_type[0..0] rescue 'X'}), LINEUP => [#{team1.players.size} v #{team2.players.size} (#{@spectator.players.size})]"
      end

    end

  end
end
