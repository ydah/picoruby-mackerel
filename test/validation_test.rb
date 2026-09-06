class MackerelValidationTest < Picotest::Test
  class Clock
    attr_accessor :now, :ready

    def initialize
      @now = 1_788_670_800
      @ready = true
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

    def initialize
      @calls = 0
    end

    def post(path:, headers:, body:)
      @calls += 1
      Mackerel::Response.new(status_code: 200, headers: {}, body: '{"success":true}')
    end
  end

  def setup
    @clock = Clock.new
    @transport = Transport.new
  end

  def client(options = {})
    Mackerel::Client.new(
      api_key: options['api_key'] || 'test-key-not-a-secret',
      service: options.key?('service') ? options['service'] : 'sensors',
      host_id: options['host_id'],
      clock: @clock,
      transport: @transport
    )
  end

  def metric(name = 'custom.sensor.temperature', time = :current, value = 1)
    {'name' => name, 'time' => time == :current ? @clock.now : time, 'value' => value}
  end

  def test_requires_exactly_one_destination
    assert_raise(Mackerel::ConfigurationError) do
      Mackerel::Client.new(api_key: 'key', clock: @clock, transport: @transport)
    end
    assert_raise(Mackerel::ConfigurationError) do
      Mackerel::Client.new(
        api_key: 'key', service: 'service', host_id: 'host', clock: @clock, transport: @transport
      )
    end
  end

  def test_rejects_unsafe_configuration
    ['', "key\nvalue", "key\0value", 'a' * 257].each do |api_key|
      assert_raise(Mackerel::ConfigurationError) { client('api_key' => api_key) }
    end
    ['bad/path', 'bad?query', 'bad#fragment', "bad\nvalue", 'a' * 65].each do |service|
      assert_raise(Mackerel::ConfigurationError) { client('service' => service) }
    end
    assert_equal(0, @transport.calls)
  end

  def test_rejects_invalid_batch_shape
    target = client
    [nil, {}, [], [metric] * 9].each do |metrics|
      assert_raise(Mackerel::InputError) { target.post(metrics) }
    end
    assert_equal(0, @transport.calls)
  end

  def test_rejects_non_finite_and_unsafe_values
    invalid = [nil, true, false, '1', 9_007_199_254_740_992, -9_007_199_254_740_992]
    invalid << Float::NAN
    invalid << Float::INFINITY
    invalid.each do |value|
      assert_raise(Mackerel::InputError) { client.post([metric('custom.sensor.value', :current, value)]) }
    end
    assert_equal(0, @transport.calls)
  end

  def test_accepts_finite_numeric_values
    target = client
    [0, -20, 23.5, 9_007_199_254_740_991].each do |value|
      assert(target.post([metric('custom.sensor.value', :current, value)]).success?)
    end
    assert_equal(4, @transport.calls)
  end

  def test_rejects_invalid_times
    target = client
    [nil, 0, -1, 1_788_670_800.0, @clock.now - 301, @clock.now + 6, 1_788_670_800_000].each do |time|
      assert_raise(Mackerel::InputError) { target.post([metric('custom.sensor.value', time, 1)]) }
    end
    assert_equal(0, @transport.calls)
  end

  def test_rejects_invalid_and_duplicate_names
    target = client
    ['', 'sensor.value', 'custom.', 'custom..value', 'custom.sensor/value', "custom.sensor\nvalue", 'custom.' + 'a' * 122].each do |name|
      assert_raise(Mackerel::InputError) { target.post([metric(name)]) }
    end
    assert_raise(Mackerel::InputError) { target.post([metric, metric]) }
    assert_equal(0, @transport.calls)
  end

  def test_does_not_send_before_clock_is_ready
    @clock.ready = false
    assert_raise(Mackerel::ClockNotReadyError) { client.post([metric]) }
    assert_equal(0, @transport.calls)
  end

  def test_does_not_expose_the_api_key
    target = client('api_key' => 'super-secret-value')
    assert_false(target.inspect.include?('super-secret-value'))
    assert_raise(Mackerel::InputError) { target.post([]) }
    assert_equal(0, @transport.calls)
  end
end
