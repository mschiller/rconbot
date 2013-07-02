module RconBot
  class Bot
    attr_reader :passive_mode, :rcon_connection, :log_filename, :match

    def initialize(options = {})
      @team1 = options[:team1] || 'team1'
      @team2 = options[:team2] || 'team2'
      @maps = options[:maps] || []
      @rotate = options[:rotate] || false
      @passive_mode = options[:passive_mode] || false
      @sv_password = options[:sv_password] || rand(9000) + 1000 # 4 digit password to be mailed to captains
    end
    
    def connect(host, port, password, log_filename)
      @log_filename = log_filename
      @rcon_connection = RconConnection.new(host, port, password)

      @rcon_connection.command("sv_password \"#{@sv_password}\"")
      @rcon_connection.command("kick all 'Sorry, scheduled match to take place. Visit www.fragg.in to participate.'") unless @passive_mode

      begin
        if @maps.empty?
          administer
        else
          @maps.each do |map|
            administer(map)
          end
        end
      end while @rotate
      @rcon_connection.disconnect
    end

    def administer(map = nil)
      @rcon_connection.command("hostname MetalZone Match - #{@team1} vs #{@team2} [rconbot.com]")
      ttl = 1 * 60 # max 10 minutes for warmup
      @match = Match.new(self, @team1, @team2, map)

      begin
        @match.setup
        # first half
        Timeout::timeout(ttl) do 
          @match.warm_up unless @passive_mode
        end
        @match.start
        # second half
        Timeout::timeout(ttl) do 
          @match.warm_up unless @passive_mode
        end
        @match.start
        @match.finish
      rescue Timeout::Error
        @rcon_connection.command("say Match time expired, map will change...")
      end
    end
  end
end
