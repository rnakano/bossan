require 'rack'
require 'optparse'
require 'net/http'

KNOWN_SERVERS = [:webrick, :thin, :bossan]
START_PORT = 8000
N = 1000
C = 1

servers = [:webrick, :bossan]
n = N
c = C

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

handlers = servers.map{|s|
  case s
  when :webrick
    require 'webrick'
    Rack::Handler::WEBrick
  when :thin
    require 'thin'
    Rack::Handler::Thin
  when :bossan
    require 'bossan'
    Rack::Handler::Bossan
  end
}

def wait
  sleep 0.5
end

def send_requests addr, port, n, c
  c.times.map{
    Thread.start{
      (n/c).times {
        Net::HTTP.start(addr, port){|http|
          response = http.get("/")
          raise "Body error" unless response.body != "hi"
        }
      }
    }
  }.each{|t| t.join}
end

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
  send_requests("localhost", port, n, c)
  dt = Time.now - timer
  Process.kill(:INT, pid)
  dt
}.tap{
  puts ""
  puts "Benchmark results:"
}.zip(servers){|dt, s|
  rps = 1.0 / (dt / N)
  printf("%s\t\t%7.2f requests / sec (%5.4f sec)\n", s, rps, dt)
}
