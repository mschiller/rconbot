module RconBot
  
  class Team
    attr_reader :name, :dead_players, :score
    attr_accessor :first_half_score, :second_half_score, :players
    
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
      @all_players = Set.new
      @dead_players = Set.new
      @first_half_score = 0
      @second_half_score = 0
      super()
    end

    def add_player(player)
      @players.add(player)
      @all_players.add(player)
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

    def score
      @first_half_score + @second_half_score
    end
    
  end

end
