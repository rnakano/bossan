# -*- coding: utf-8 -*-
require 'test/unit'
require 'pp'
require 'net/http'
require_relative '../lib/bossan'


class RackEnvSimpleQueryTest < Test::Unit::TestCase

  RESPONSE = ["Hello ", "world!"].freeze
  DEFAULT_HOST = "localhost"
  DEFAULT_PORT = 8000

  def test_query_app
    r, w = IO.pipe
    pid = fork do
      r.close
      trap(:INT) { Bossan.stop }
      Bossan.listen(DEFAULT_HOST, DEFAULT_PORT)
      Bossan.run(proc {|env|
                   @env = env.dup
                   # I have no idea how to check this two values..
                   @env.delete "rack.input"
                   @env.delete "rack.errors"
                   w.write Marshal.dump(@env)
                   w.close
                   body = RESPONSE
                   [200,
                    {
                      'Content-type'=> 'text/plain',
                      'Content-length'=> RESPONSE.join.size.to_s
                    },
                    body
                   ]
                 })
    end
    Process.detach pid
    sleep 2

    Net::HTTP.start(DEFAULT_HOST, DEFAULT_PORT){|http|
      http.get("/ABC/DEF?a=1234&bbbb=ccc")
    }

    w.close
    env = Marshal.load(r.read)
    r.close

    assert_equal(env["PATH_INFO"], "/ABC/DEF")
    assert_equal(env["QUERY_STRING"], "a=1234&bbbb=ccc")
  ensure
    Process.kill(:INT, pid)
  end

end
