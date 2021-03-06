module RconBot
  class RconConnection
    def initialize(host, port, password, type = 'l')
      @host = host
      @port = port
      @password = password
      @server_type = type
      connect
      get_challenge_id
    end
    
    def get_challenge_id
      response = socket_request("\xFF" * 4 + "challenge rcon" + "\x00")
      if challenge_id = /challenge rcon (\d+)/.match(response)
        @challenge_id = challenge_id[1]
      end
    end
    
    def command(request)
      socket_request("\xFF" * 4 + "rcon #{@challenge_id} \"#{@password}\" #{request}" + "\x00")
    end
    
    def connect
      @socket = UDPSocket.new
      @socket.connect(@host, @port)
    end

    def disconnect
      @socket.close
    end

    def socket_request(request)
      puts "=> #{request.inspect}"
      @socket.print(request)
      retval = []
      loop do 
        select([@socket], nil, nil, 10)
        str = @socket.recv(65507)
        #puts "<= #{str.inspect}"
        bytes = str.unpack("c*")
        retval += bytes
        break
      end
      return retval.pack('c*')
    end
  end
end
