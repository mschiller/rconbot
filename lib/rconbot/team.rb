module RconBot
  
  class Team
    attr_reader :name, :score, :players
    
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
    
  end

end
