require 'json'
require 'net/http'
require 'time'

module Mackerel
  VERSION = '0.1.0'

  MAX_API_KEY_BYTES = 256
  MAX_IDENTIFIER_BYTES = 64
  MAX_METRIC_NAME_BYTES = 128
  MAX_METRICS = 8
  MAX_BODY_BYTES = 1_536
  MAX_REQUEST_BYTES = 2_048
  MAX_INTEGER_VALUE = 9_007_199_254_740_991
  MAX_PAST_SECONDS = 300
  MAX_FUTURE_SECONDS = 5
  MAX_RETRY_AFTER_SECONDS = 2_147_483_647

  class Error < StandardError; end
  class ConfigurationError < Error; end
  class InputError < Error; end
  class ClockNotReadyError < Error; end
  class UnsupportedTransportError < Error; end

  class TransportFailure < Error
    attr_reader :reason, :phase, :retryable

    def initialize(reason:, phase:, retryable:)
      @reason = reason
      @phase = phase
      @retryable = retryable
      super('Mackerel transport failed')
    end

    def inspect
      "#<#{self.class}: #{@reason}>"
    end
  end

  class Response
    attr_reader :status_code, :headers, :body

    def initialize(status_code:, headers:, body:)
      @status_code = status_code
      @headers = headers || {}
      @body = body || ''
    end
  end

  class Result
    attr_reader :http_status, :error_code, :delivery, :retry_after_seconds

    def initialize(success:, retryable:, http_status:, error_code:, delivery:, retry_after_seconds: nil)
      @success = success
      @retryable = retryable
      @http_status = http_status
      @error_code = error_code
      @delivery = delivery
      @retry_after_seconds = retry_after_seconds
    end

    def success?
      @success
    end

    def retryable?
      @retryable
    end
  end

  class Client
    def initialize(api_key:, clock:, transport:, service: nil, host_id: nil)
      validate_api_key(api_key)
      validate_destination(service, host_id)
      raise ConfigurationError, 'clock is required' unless clock
      raise ConfigurationError, 'transport is required' unless transport

      @api_key = api_key
      @clock = clock
      @transport = transport
      @service = service
      @host_id = host_id
    end

    def post(metrics)
      now = current_time
      payload = validate_metrics(metrics, now)
      body = JSON.generate(payload)
      raise InputError, 'request body is too large' if body.bytesize > MAX_BODY_BYTES

      path = @service ? "/api/v0/services/#{@service}/tsdb" : '/api/v0/tsdb'
      headers = request_headers(body)
      raise InputError, 'HTTP request is too large' if request_bytes(path, headers, body) > MAX_REQUEST_BYTES

      response = @transport.post(path: path, headers: headers, body: body)
      result_for(response)
    rescue TransportFailure => failure
      Result.new(
        success: false,
        retryable: failure.retryable,
        http_status: nil,
        error_code: failure.reason,
        delivery: failure.phase == :before_request ? :not_sent : :unknown
      )
    end

    def inspect
      "#<#{self.class}>"
    end

    private

    def validate_api_key(api_key)
      unless api_key.is_a?(String) && !api_key.empty? && api_key.bytesize <= MAX_API_KEY_BYTES
        raise ConfigurationError, 'invalid API key'
      end
      each_byte(api_key) do |byte|
        raise ConfigurationError, 'invalid API key' if byte < 32 || byte == 127
      end
    end

    def validate_destination(service, host_id)
      if service.nil? == host_id.nil?
        raise ConfigurationError, 'specify exactly one destination'
      end
      validate_identifier(service || host_id)
    end

    def validate_identifier(value)
      unless value.is_a?(String) && !value.empty? && value.bytesize <= MAX_IDENTIFIER_BYTES
        raise ConfigurationError, 'invalid destination'
      end
      each_byte(value) do |byte|
        next if ascii_alphanumeric?(byte) || byte == 95 || byte == 45
        raise ConfigurationError, 'invalid destination'
      end
    end

    def current_time
      unless @clock.respond_to?(:ready?) && @clock.ready?
        raise ClockNotReadyError, 'clock is not ready'
      end
      now = @clock.unix_seconds
      unless now.is_a?(Integer) && now > 0
        raise ClockNotReadyError, 'clock returned an invalid time'
      end
      now
    end

    def validate_metrics(metrics, now)
      unless metrics.is_a?(Array) && 0 < metrics.length && metrics.length <= MAX_METRICS
        raise InputError, 'metrics must contain 1 to 8 items'
      end

      names = {}
      metrics.map do |metric|
        raise InputError, 'metric must be a Hash' unless metric.is_a?(Hash)
        name = metric['name']
        time = metric['time']
        value = metric['value']
        validate_metric_name(name)
        raise InputError, 'duplicate metric name' if names[name]
        names[name] = true
        validate_metric_time(time, now)
        validate_metric_value(value)

        copy = {'name' => name, 'time' => time, 'value' => value}
        copy['hostId'] = @host_id if @host_id
        copy
      end
    end

    def validate_metric_name(name)
      unless name.is_a?(String) && name.start_with?('custom.') && name.bytesize <= MAX_METRIC_NAME_BYTES
        raise InputError, 'invalid metric name'
      end

      previous_dot = false
      each_byte(name) do |byte|
        if byte == 46
          raise InputError, 'invalid metric name' if previous_dot
          previous_dot = true
        elsif ascii_alphanumeric?(byte) || byte == 95 || byte == 45
          previous_dot = false
        else
          raise InputError, 'invalid metric name'
        end
      end
      raise InputError, 'invalid metric name' if previous_dot
    end

    def validate_metric_time(time, now)
      unless time.is_a?(Integer) && time > 0 && now - MAX_PAST_SECONDS <= time && time <= now + MAX_FUTURE_SECONDS
        raise InputError, 'invalid metric time'
      end
    end

    def validate_metric_value(value)
      if value.is_a?(Integer)
        raise InputError, 'metric value loses JSON precision' if value.abs > MAX_INTEGER_VALUE
        return
      end
      if value.is_a?(Float) && value == value && value - value == 0.0
        return
      end
      raise InputError, 'metric value must be finite'
    end

    def request_headers(body)
      {
        'Host' => 'api.mackerelio.com',
        'X-Api-Key' => @api_key,
        'Content-Type' => 'application/json',
        'Accept' => 'application/json',
        'Accept-Encoding' => 'identity',
        'Connection' => 'close',
        'Content-Length' => body.bytesize.to_s
      }
    end

    def request_bytes(path, headers, body)
      size = "POST #{path} HTTP/1.1\r\n".bytesize + 2 + body.bytesize
      headers.each { |key, value| size += key.bytesize + value.bytesize + 4 }
      size
    end

    def result_for(response)
      status = response.status_code
      unless status.is_a?(Integer) && 100 <= status && status <= 599
        return failure_result(:invalid_response, nil, false, :unknown)
      end

      if status == 200
        return success_result if valid_success_body?(response.body)
        return failure_result(:invalid_success_response, status, false, :unknown)
      end
      if status == 429
        retry_after = retry_after_seconds(response.headers)
        return failure_result(:retry_after_too_large, status, false, :rejected) if retry_after == :too_large
        return failure_result(:rate_limited, status, true, :rejected, retry_after)
      end
      if [408, 500, 502, 503, 504].include?(status)
        return failure_result(:temporary_http_error, status, true, :unknown)
      end
      if 300 <= status && status < 400
        return failure_result(:redirect_refused, status, false, :rejected)
      end
      if [400, 401, 403, 404, 413, 422].include?(status)
        return failure_result(:http_rejected, status, false, :rejected)
      end
      failure_result(:unexpected_http_status, status, false, :unknown)
    end

    def valid_success_body?(body)
      parsed = JSON.parse(body)
      parsed.is_a?(Hash) && parsed['success'] == true
    rescue
      false
    end

    def retry_after_seconds(headers)
      value = nil
      headers.each do |key, header_value|
        value = header_value if key.to_s.downcase == 'retry-after'
      end
      return nil unless value.is_a?(String) && !value.empty?

      number = 0
      each_byte(value) do |byte|
        return nil unless 48 <= byte && byte <= 57
        return :too_large if number > (MAX_RETRY_AFTER_SECONDS - (byte - 48)) / 10
        number = number * 10 + byte - 48
      end
      number
    end

    def success_result
      Result.new(success: true, retryable: false, http_status: 200, error_code: nil, delivery: :accepted)
    end

    def failure_result(error_code, status, retryable, delivery, retry_after = nil)
      Result.new(
        success: false,
        retryable: retryable,
        http_status: status,
        error_code: error_code,
        delivery: delivery,
        retry_after_seconds: retry_after
      )
    end

    def each_byte(string)
      index = 0
      while (byte = string.getbyte(index))
        yield byte
        index += 1
      end
    end

    def ascii_alphanumeric?(byte)
      (48 <= byte && byte <= 57) || (65 <= byte && byte <= 90) || (97 <= byte && byte <= 122)
    end
  end
end

