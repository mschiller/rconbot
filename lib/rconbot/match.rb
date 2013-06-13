module RconBot

  class Match
    attr_reader :half_length, :team_size, :result, :team1, :team2, :stats, :half, :map, :rcon_connection
    attr_accessor :score, :result

    include AASM
    
    aasm do
      state :wait_on_join, :initial => true, :before_enter => :change_level
      state :warm_up
      state :first_half
      state :second_half
      state :finished

      event :warm_up do
        after do 
          exec_warmup_cfg
        end
        transitions :from => :wait_on_join, :to => :warm_up
      end
      
      event :wait_on_join do
        after do
          exec_pub_cfg
        end
        transitions :from => :warm_up, :to => :wait_on_join
      end

      event :live do
        after do
          exec_live_cfg
        end
        transitions :from => :warm_up, :to => [:first_half, :second_half]
      end

      event :half_time do
        after do 
          exec_warmup_cfg
        end
        transitions :from => :first_half, :to => :warm_up
      end

      event :full_time do
        transitions :from => :second_half, :to => :finished
      end
    end
    
    def initialize(team1, team2, map, rcon_connection)
      @live = false
      @team_size = 5
      @half = 0
      @half_length = 15
      @team1 = team1
      @team2 = team2
      @score = [[0, 0], [0, 0]]
      @rcon_connection = rcon_connection
      @alive = {'CT' => @team_size, 'TERRORIST' => @team_size}
    end
    
    def exec_warmup_cfg
      @rcon_connection.command("exec warmup.cfg")
    end

    def exec_pub_cfg
      @rcon_connection.command("exec pub.cfg")
    end

    def exec_live_cfg
      @rcon_connection.command("exec live.cfg")
    end
    
    def change_level
      @rcon_connection.command("changelevel #{@map}") if @map
    end

    def warmup
      puts "WARMUP"
      @status += 1
      @live = false
    end

    def start
      puts "STARTED"
      @status += 1
      next_round
    end

    def live
      puts "LIVE"
      @live = true
    end

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

    def log_filename
      '/home/hlds/hlds_screen.log' # '/tmp/test.log'
    end

  end
end
