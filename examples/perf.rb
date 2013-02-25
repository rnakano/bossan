require 'rack'
require 'optparse'
require 'net/http'

KNOWN_SERVERS = [:webrick, :thin, :bossan]
START_PORT = 8000
servers = KNOWN_SERVERS.dup

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

def send_requests addr, port, n
  n.times {
    Net::HTTP.start(addr, port){|http|
      response = http.get("/")
      raise "Body error" unless response.body != "hi"
    }
  }
end

Net::HTTP.version_1_2

N = 1000
ports = (START_PORT...(START_PORT+servers.size))
servers.zip(handlers, ports).map{|s, handler, port|
  pid = fork do
    trap(:INT) { handler.shutdown }
    handler.run MyApp.new, :Port => port, :AccessLog => []
  end
  Process.detach(pid)
  wait
  timer = Time.now
  send_requests("localhost", port, N)
  dt = Time.now - timer
  Process.kill(:INT, pid)
  dt
}.zip(servers){|dt, s|
  rps = 1.0 / (dt / N)
  printf("%s\t\t%1.2f requests / sec (\t%1.4f sec)\n", s, rps, dt)
}
