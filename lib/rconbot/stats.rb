module RconBot
  class Stats

    attr_accessor :alias, :player, :weapon, :match

    def initialize(team1, team2)
      @alias = (team1.players | team2.players).inject({}) do |h, i|
        h[i] = {}
        h
      end
      @player = {}
      @weapon = {}
    end

    def save
      conn = Redis.new
      # write the stats
      conn.close
    end
  end
end
