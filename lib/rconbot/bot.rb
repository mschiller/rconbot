module RconBot
  class Bot
    attr_accessor :match

    # options :team1 :team2 :maps :timelimit
    def connect(host, port, password, options = {})
      options[:team1] ||= 'team1'
      options[:team2] ||= 'team2'
      options[:maps] ||= []
      options[:repeat] ||= false
      options[:password] ||= rand(100) # to be mailed to captains
      
      @rcon_connection = RconConnection.new(host, port, password)
      @rcon_connection.command("sv_password \"#{options[:password]}\"")

      # kick everyone
      # @rcon_connection.command("kick all 'Sorry, scheduled match to take place. Visit www.fragg.in to participate.'")

      begin
        if options[:maps].empty?
          administer(options[:team1], options[:team2])
        else
          options[:maps].each do |map|
            administer(options[:team1], options[:team2], map)
          end
        end
      end while options[:repeat]
      @rcon_connection.disconnect
    end

    def administer(team1, team2, map = nil)
      team1 = Team.new(team1)
      team2 = Team.new(team2)
      @match = Match.new(team1, team2, map, @rcon_connection, log_filename)
      @match.run
      @match.warm_up
      @match.live
      @match.halftime
      @match.live
      @match.fulltime
    end

    def log_filename
      '/home/hlds/hlds_screen.log'
    end
  end
end
