module RconBot
  
  class Team
    include AASM
    attr_reader :name, :score, :players
    
    aasm do
      state :not_ready, :initial => true
      state :ready
      
      event :ready do
        transitions :from => :not_ready, :to => :ready
      end
    end
    
    def initialize(team1)
      @name = name
      @players = Set.new
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
