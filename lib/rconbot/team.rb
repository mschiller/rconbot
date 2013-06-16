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
      @players.length
    end

    def won?
      
    end

    def respawn
      @dead_players = Set.new
    end

    def kill_player(player)
      @dead_players.add(player)
    end

    
  end

end
