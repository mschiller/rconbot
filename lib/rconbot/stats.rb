module RconBot
  class Stats

    attr_accessor :team1, :team2

    def initialize(team1, team2)
      @alias = (team1.players | team2.players).inject({}) do |h, i|
        h[i] = {}
      end
      @player = (team1.players | team2.players).inject({}) do |h, i| 
        h[i] = {:kills => 0, :deaths => 0, :points => {'CT' => 0, 'TERRORIST' => 0}}
        h
      end
      @weapon = {}
    end

    def save
      conn = Redis.new
      # write the stats
      conn.close
    end
  end
end
