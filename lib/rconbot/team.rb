module RconBot
  
  class Team
    attr_reader :name, :players, :dead_players
    attr_accessor :score
    
    state_machine :initial => :not_ready do
      state :ready
      state :not_ready
      
      event :is_ready do
        transition :not_ready => :ready
      end

      event :is_not_ready do
        transition :ready => :not_ready
      end
    end
    
    def initialize(name)
      @name = name
      @players = Set.new
      @dead_players = Set.new
      super()
    end

    def add_player(player)
      @players.add(player)
    end

    def remove_player(player)
      @players.delete(player)
    end

    def size
      @players.size
    end

    def won?
      
    end

    def respawn
      @dead_players = Set.new
    end

    def player_died(player)
      @dead_players.add(player)
    end

    def alive_count
      (@players - @dead_players).size
    end
    
    def dead_count
      @dead_players.size
    end
    
  end

end
