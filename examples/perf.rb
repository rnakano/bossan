require 'rack'
require 'optparse'
require 'net/http'
require 'thread'

KNOWN_SERVERS = [:webrick, :thin, :bossan]
START_PORT = 8000
N = 1000
C = 1

servers = [:webrick, :bossan]
n = N
c = C

class MyApp
  def call env
    body = ['hi!']
    # pp env
    [
     200, # Status code
     { 'Content-Type' => 'text/html',
       'Content-Length' => body.join.size.to_s,
     }, # Reponse headers
     body # Body of the response
    ]
  end
end

def wait
  sleep 0.5
end

def send_requests addr, port, n, c
  success = true
  lock = Mutex.new
  c.times.map{
    Thread.start(lock){|lock|
      begin
        (n/c).times {
          Net::HTTP.start(addr, port){|http|
            response = http.get("/")
            raise "Error: status code is not 200, but #{response.code}" unless response.code.to_i == 200
            raise "Error: body broken" unless response.body == "hi!"
          }
        }
      rescue => e
        puts e.to_s
        lock.synchronize {
          success = false
        }
      end
    }
  }.each{|t| t.join}
  success
end


opt = OptionParser.new
opt.on("-s Servers", "list of servers (default: webrick,bossan)"){|s|
  servers = s.split(",").map(&:downcase).map(&:intern) & KNOWN_SERVERS
}
opt.on("-n TotalRequests", "number of total requests (default: 1000)"){|reqs|
  n = reqs.to_i
}
opt.on("-c Connections", "number of total connections (default: 1)"){|cons|
  c = cons.to_i
}
opt.parse!(ARGV)

server_map = servers.map{|s|
  case s
  when :webrick
    require 'webrick'
    [Rack::Handler::WEBrick, WEBrick::VERSION]
  when :thin
    require 'thin'
    [Rack::Handler::Thin, Thin::VERSION::STRING]
  when :bossan
    require 'bossan'
    [Rack::Handler::Bossan, Bossan::VERSION]
  end
}
handlers = server_map.map{|a| a[0]}
versions = server_map.map{|a| a[1]}

Net::HTTP.version_1_2

ports = (START_PORT...(START_PORT+servers.size))
servers.zip(handlers, ports).map{|s, handler, port|
  puts "Running benchmark #{s}..."
  pid = fork do
    trap(:INT) { handler.shutdown }
    handler.run MyApp.new, :Port => port, :AccessLog => []
  end
  Process.detach(pid)
  wait
  timer = Time.now
  success = send_requests("localhost", port, n, c)
  dt = Time.now - timer
  Process.kill(:INT, pid)
  if success
    dt
  else
    nil
  end
}.tap{
  puts ""
  puts "==Benchmark settings=="
  puts "ruby: " + RUBY_DESCRIPTION
  puts "requests: #{n}"
  puts "connections: #{c}"
  puts "servers: " + servers.zip(versions).map{|s, v|
    "#{s} (#{v})"
  }.join(", ")
  puts""
  puts "==Benchmark results=="
}.zip(servers){|dt, s|
  if dt
    rps = 1.0 / (dt / n)
    printf("%s\t\t%7.2f requests / sec (%5.4f sec)\n", s, rps, dt)
  else
    printf("%s\t\terror occurs. skip\n", s)
  end
}
