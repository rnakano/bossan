require_relative '../lib/bossan'
require 'minitest/unit'
require 'test/unit/testcase'
require 'net/http'


DEFAULT_HOST = "localhost"
DEFAULT_PORT = 8000
ASSERT_RESPONSE = "Hello world!"
RESPONSE = ["Hello ", "world!"].freeze


class ErrApp
  def call env
    body = RESPONSE
    [500,
     {
       'Content-type'=> 'text/html',
     },
     RESPONSE
    ]
  end
end


class RackErrSpecTest < Test::Unit::TestCase
  def test_error
    response = Net::HTTP.start(DEFAULT_HOST, DEFAULT_PORT) {|http|
      http.get("/")
    }
    assert_equal("500", response.code)
    assert_equal(ASSERT_RESPONSE, response.body)
  end
end


def server_is_wake_up? n=100
  n.times {
    begin
      Net::HTTP.start(DEFAULT_HOST, DEFAULT_PORT)
    rescue
      next
    end
    $stderr.puts "*** running success ***"
    return true
  }
  return false
end



begin
  $stderr.puts RUBY_DESCRIPTION
  pid = fork do
    trap(:INT) { Bossan.stop }
    Bossan.listen(DEFAULT_HOST, DEFAULT_PORT)
    Bossan.run(ErrApp.new)
  end

  Process.detach pid

  unless server_is_wake_up?
    $stderr.puts "bossan won't wake up until you love it ..."
    exit 1
  end

  err = MiniTest::Unit.new.run(ARGV)
  exit false if err && err != 0

ensure
  Process.kill(:INT, pid)
end