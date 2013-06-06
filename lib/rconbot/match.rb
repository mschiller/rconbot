module RconBot
  class Match
    attr_reader :half_length, :team_size, :result, :team1, :team2, :stats, :half, :map
    attr_accessor :score, :result, :status, :alive

    STATUS = [:wait_on_join, :first_warmup, :first_half, :second_warmup, :second_half, :finished]
    
    def initialize(team1 = '1', team2 = '2', map = 'dust2')
      @live = false
      @team_size = 5
      @half = 0
      @half_length = 2
      @team1 = team1
      @team2 = team2
      @score = [[0, 0], [0, 0]]
      @status = 0
      @alive = {'CT' => @team_size, 'TERRORIST' => @team_size}
    end

    def current_status
      STATUS[@status]
    end

    def end_half
      stop
      @half += 1
      @status += 1
    end

    def end_match(result)
      stop
      @result = result
      @status = :finished
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

    def log_filename
      '/home/hlds/hlds_screen.log' # '/tmp/test.log'
    end

  end
end
