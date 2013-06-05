module RconBot
  class Match
    attr_reader :half_length, :team_size, :result, :team1, :team2, :stats, :half
    attr_accessor :score, :result, :status, :alive
    
    def initialize(team1 = '1', team2 = '2', map = 'dust2')
      @live = false
      @team_size = 5
      @half = 0
      @half_length = 1
      @team1 = team1
      @team2 = team2
      @score = [[0, 0], [0, 0]]
      @stats = Stats.new(team1, team2, map)
      @status = :wait_on_join # :wait_on_join :first_warmup :first_half :second_warmup :second_half :finished
      @alive = {'CT' => @team_size, 'TERRORIST' => @team_size}
    end

    def switch
      @match.stop
      @match.half += 1
      @match.status = :second_warmup
    end

    def teams
      [@team1, @team2]
    end
    
    # def half
    #   return 0 if status == :first_half
    #   return 1 if status == :second_half
    #   return nil
    # end
    
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
end
