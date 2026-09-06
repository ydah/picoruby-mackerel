class MackerelResponseTest < Picotest::Test
  class Clock
    def ready?
      true
    end

    def unix_seconds
      1_788_670_800
    end
  end

  class Transport
    def initialize(response)
      @response = response
    end

    def post(path:, headers:, body:)
      raise @response if @response.is_a?(Mackerel::TransportFailure)
      @response
    end
  end

  def response_result(status, body = '{}', headers = {})
    response = Mackerel::Response.new(status_code: status, headers: headers, body: body)
    client = Mackerel::Client.new(
      api_key: 'test-key-not-a-secret',
      service: 'sensors',
      clock: Clock.new,
      transport: Transport.new(response)
    )
    client.post([{'name' => 'custom.sensor.value', 'time' => 1_788_670_800, 'value' => 1}])
  end

  def test_only_complete_success_contract_succeeds
    accepted = response_result(200, '{"success":true}')
    assert(accepted.success?)
    assert_equal(:accepted, accepted.delivery)
    assert_false(response_result(201, '{"success":true}').success?)
    assert_false(response_result(200, '').success?)
    assert_false(response_result(200, '{broken').success?)
    assert_false(response_result(200, '{"success":false}').success?)
  end

  def test_classifies_http_failures
    [408, 500, 502, 503, 504].each do |status|
      response = response_result(status)
      assert(response.retryable?)
      assert_equal(:unknown, response.delivery)
    end
    [400, 401, 403, 404, 413, 422].each do |status|
      response = response_result(status)
      assert_false(response.retryable?)
      assert_equal(:rejected, response.delivery)
    end
    redirect = response_result(302)
    assert_equal(:redirect_refused, redirect.error_code)
    assert_false(redirect.retryable?)
  end

  def test_parses_only_retry_after_delta_seconds
    valid = response_result(429, '{}', {'Retry-After' => '120'})
    assert(valid.retryable?)
    assert_equal(120, valid.retry_after_seconds)
    assert_nil(response_result(429, '{}', {'retry-after' => ''}).retry_after_seconds)
    assert_nil(response_result(429, '{}', {'Retry-After' => 'Sun, 06 Sep 2026 12:00:00 GMT'}).retry_after_seconds)

    too_large = response_result(429, '{}', {'Retry-After' => '2147483648'})
    assert_false(too_large.retryable?)
    assert_equal(:retry_after_too_large, too_large.error_code)
  end

  def test_preserves_transport_delivery_uncertainty
    before_request = Mackerel::TransportFailure.new(
      reason: :dns_failed, phase: :before_request, retryable: true
    )
    request_started = Mackerel::TransportFailure.new(
      reason: :read_timeout, phase: :request_started, retryable: true
    )

    first = result_for_failure(before_request)
    second = result_for_failure(request_started)
    assert_equal(:not_sent, first.delivery)
    assert_equal(:unknown, second.delivery)
    assert(first.retryable?)
    assert(second.retryable?)
  end

  def result_for_failure(failure)
    client = Mackerel::Client.new(
      api_key: 'test-key-not-a-secret',
      service: 'sensors',
      clock: Clock.new,
      transport: Transport.new(failure)
    )
    client.post([{'name' => 'custom.sensor.value', 'time' => 1_788_670_800, 'value' => 1}])
  end
end
