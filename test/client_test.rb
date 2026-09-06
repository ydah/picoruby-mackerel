class MackerelClientTest < Picotest::Test
  class Clock
    attr_accessor :now, :ready

    def initialize(now = 1_788_670_800, ready = true)
      @now = now
      @ready = ready
    end

    def ready?
      @ready
    end

    def unix_seconds
      @now
    end
  end

  class Transport
    attr_reader :calls

    def initialize(response = nil)
      @response = response || Mackerel::Response.new(
        status_code: 200,
        headers: {},
        body: '{"success":true}'
      )
      @calls = []
    end

    def post(path:, headers:, body:)
      @calls << {'path' => path, 'headers' => headers, 'body' => body}
      @response
    end
  end

  def setup
    @clock = Clock.new
    @transport = Transport.new
  end

  def metric(name = 'custom.sensor.temperature', value = 23.75)
    {'name' => name, 'time' => @clock.now, 'value' => value}
  end

  def test_posts_service_metrics_once
    client = Mackerel::Client.new(
      api_key: 'test-key-not-a-secret',
      service: 'sensors',
      clock: @clock,
      transport: @transport
    )

    result = client.post([metric])
    call = @transport.calls[0]
    payload = JSON.parse(call['body'])

    assert(result.success?)
    assert_equal(1, @transport.calls.length)
    assert_equal('/api/v0/services/sensors/tsdb', call['path'])
    assert_equal('test-key-not-a-secret', call['headers']['X-Api-Key'])
    assert_equal('identity', call['headers']['Accept-Encoding'])
    assert_equal('close', call['headers']['Connection'])
    assert_equal('PicoRuby-Net-HTTP/1.0', call['headers']['User-Agent'])
    assert_equal(23.75, payload[0]['value'])
  end

  def test_posts_host_metrics_without_mutating_input
    source = metric
    client = Mackerel::Client.new(
      api_key: 'test-key-not-a-secret',
      host_id: 'host_1',
      clock: @clock,
      transport: @transport
    )

    client.post([source])
    call = @transport.calls[0]
    payload = JSON.parse(call['body'])

    assert_equal('/api/v0/tsdb', call['path'])
    assert_equal('host_1', payload[0]['hostId'])
    assert_nil(source['hostId'])
  end

  def test_accepts_one_and_eight_metrics
    client = Mackerel::Client.new(
      api_key: 'test-key-not-a-secret',
      service: 'sensors',
      clock: @clock,
      transport: @transport
    )
    metrics = []
    8.times { |index| metrics << metric("custom.sensor.value_#{index}", index) }

    assert(client.post([metric]).success?)
    assert(client.post(metrics).success?)
    assert_equal(2, @transport.calls.length)
  end
end
