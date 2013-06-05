module RconBot
  class Bot
    attr_accessor :match
    
    # options :team1 :team2 :maps :timelimit
    def connect(host, port, password, options = {})
      options[:team1] ||= 'team1'
      options[:team2] ||= 'team2'
      options[:maps] ||= ['de_dust2']
      options[:sv_password] ||= rand(100) # to be mailed to captains
      
      # connect as rcon
      @rcon_connection = RconConnection.new(host, port, password)
      # set a password
      @rcon_connection.command("sv_password \"#{options[:sv_password]}\"")

      # monitor the logs 
      filename = log_filename
      f = File.open(filename, "r")
      f.seek(0, IO::SEEK_END)

      # kick everyone
      # @rcon_connection.command("kick all 'Sorry, scheduled match to take place. Visit www.fragg.in to participate.'")

      options[:maps].each do |map|
        @match = Match.new(options[:team1], options[:team2], map)
        @rcon_connection.command("changelevel #{map}")
        @match.status = wait_on_join(f)
        [:first_half, :second_half].each do |half|
          @match.status = wait_on_ready(f, half)
          @match.status = process_match(f)
        end
      end
    end

    def wait_on_join(f)
      while true do
        select([f])
        line = f.gets
        if line =~ ENTERED_REGEX
          puts "ENTERED"
          @rcon_connection.command("exec warmup.cfg")
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
            if line =~ READY_REGEX
              puts "ALL READY"
              @rcon_connection.command("exec live.cfg")
              return status
            end
          end
        end
      rescue => e 
        @rcon_connection.command("say Rconbot is at your service...")
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
          
          if @match.round == @match.half_length
            @match.switch
            @rcon_connection.command("exec warmup.cfg")
            return :second_warmup
          else
            if @match.team_score(0) == @match.half_length + 1
              @match.stop
              @match.result = 0 # team1 (CT first T second)
            elsif @match.team_score(1) == @match.half_length + 1
              @match.stop 
              @match.result = 1 # team2
            elsif @match.round == (@match.half_length * 2)
              @match.stop
              @match.result = -1 # Draw
            end

            if @match.result
              if @match.result == -1
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

    def log_filename
      '/home/hlds/hlds_screen.log'
    end
  end
end
