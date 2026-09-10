require "socket"
require "uri"
require "thread"

module NetworkFaults
  # Forward real Redis bytes unchanged. offline! closes existing connections too,
  # so pooled connections cannot bypass the outage. Mutex/joins, never sleeps,
  # establish when the fault has taken effect.
  class RedisProxy
    attr_reader :url

    def initialize(upstream, online: true, scheme: "redis")
      @target = URI(upstream)
      raise "Unexpected test proxy protocol" unless @target.scheme == scheme
      @mutex = Mutex.new
      @online = online
      @connections = []
      @workers = []
      @server = TCPServer.new("127.0.0.1", 0)
      @url = @target.dup
      @url.host = "127.0.0.1"
      @url.port = @server.addr[1]
      @url = @url.to_s
      @acceptor = Thread.new do
        loop do
          client = @server.accept
          @mutex.synchronize do
            unless @online
              client.close
              next
            end
            upstream_socket = TCPSocket.new(@target.host, @target.port)
            @connections.concat([ client, upstream_socket ])
            [[client, upstream_socket], [upstream_socket, client]].each do |from, to|
              @workers << Thread.new do
                IO.copy_stream(from, to)
              rescue IOError, SystemCallError
                # Disconnects are the deliberately injected network fault.
              ensure
                shutdown(from)
                shutdown(to)
                # offline!/close owns socket.close; relay threads only shutdown
                # to unblock their peer without racing each other's close calls.
              end
            end
          end
        end
      rescue IOError, Errno::EBADF
        # Closing the listener terminates accept during teardown.
      end
    end

    def offline!
      @mutex.synchronize do
        @online = false
        @connections.each { |socket| shutdown(socket) }
        @connections.each { |socket| socket.close unless socket.closed? }
        @connections.clear
      end
    end

    def online!
      @mutex.synchronize { @online = true }
    end

    def close
      offline!
      @server.close
      @acceptor.join
      @workers.each(&:join)
    end

    private

    def shutdown(socket)
      socket.shutdown
    rescue IOError, SystemCallError
      # Already disconnected by its peer or by another relay thread.
    end
  end

  # Real SDK HTTP requests reach this endpoint; no Book/SearchService callbacks
  # are stubbed. Represents a temporarily unavailable engine behind HTTP.
  # Same transparent TCP transport, also exercising connection-level failures
  # against a real HTTP engine rather than only a canned HTTP 503 response.
  class HTTPProxy < RedisProxy
    def initialize(upstream)
      super(upstream, scheme: "http")
    end
  end

  class UnavailableSearch
    attr_reader :url, :requests

    def initialize
      @requests = Queue.new
      @server = TCPServer.new("127.0.0.1", 0)
      @url = "http://127.0.0.1:#{@server.addr[1]}"
      @thread = Thread.new do
        loop do
          socket = @server.accept
          request = socket.gets
          headers = []
          while (line = socket.gets) && line != "\r\n"
            headers << line
          end
          length = headers.find { |line| line.downcase.start_with?("content-length:") }.to_s.split(":", 2).last.to_i
          socket.read(length) if length.positive?
          @requests << request
          body = '{"message":"Regression: engine unavailable","code":"unavailable","type":"internal"}'
          socket.write("HTTP/1.1 503 Service Unavailable\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
          socket.close
        end
      rescue IOError, Errno::EBADF
        # Listener closed by teardown.
      end
    end

    def close
      @server.close
      @thread.join
    end
  end
end
