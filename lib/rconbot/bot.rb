module RconBot
  class Bot
    attr_accessor :match
    attr_reader :passive_mode

    # options :team1 :team2 :maps :timelimit
    def connect(host, port, password, options = {})
      options[:team1] ||= 'team1'
      options[:team2] ||= 'team2'
      options[:maps] ||= []
      options[:repeat] ||= false
      options[:passive_mode] ||= false
      options[:password] ||= rand(100) # to be mailed to captains
      
      @rcon_connection = RconConnection.new(host, port, password)
      @rcon_connection.command("sv_password \"#{options[:password]}\"")
      @passive_mode = true

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
      @rcon_connection.command("hostname MetalZone Match - #{team1} vs #{team2} [rconbot.com]")
      team1 = Team.new(team1)
      team2 = Team.new(team2)
      ttl = 1 * 60 # max 10 minutes for warmup
      @match = Match.new(team1, team2, map, @rcon_connection, log_filename)

      begin
        Timeout::timeout(ttl) do 
          @match.run
        end
        @match.warm_up_1 unless @passive_mode
        @match.start
        Timeout::timeout(ttl) do 
          @match.warm_up_2 unless @passive_mode
        end
        @match.start
        @match.fulltime
      rescue Timeout::Error
        @rcon_connection.command("say Match time expired, map will change...")
      end
    end

    def log_filename
      '/home/hlds/hlds_match_screen.log'
    end
  end
end
