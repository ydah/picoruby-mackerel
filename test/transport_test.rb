class MackerelTransportTest < Picotest::Test
  class HTTPResponse
    attr_reader :code, :header, :body

    def initialize(code = '200', header = nil, body = '{"success":true}')
      @code = code
      @header = header || {'Content-Type' => 'application/json'}
      @body = body
    end
  end

  class HTTP
    attr_accessor :use_ssl, :verify_mode, :ca_file, :open_timeout, :read_timeout
    attr_accessor :write_timeout, :total_timeout, :max_request_bytes
    attr_accessor :max_response_header_bytes, :max_response_body_bytes, :max_response_line_bytes
    attr_reader :posts, :finish_count

    def initialize(response = nil)
      @response = response || HTTPResponse.new
      @posts = []
      @finish_count = 0
      @active = false
      @start_error = nil
      @post_error = nil
    end

    def fail_start
      @start_error = true
    end

    def fail_post
      @post_error = true
    end

    def start
      raise 'secret connection detail' if @start_error
      @active = true
    end

    def post(path, body, headers)
      raise 'secret request detail' if @post_error
      @posts << [path, body, headers]
      @response
    end

    def active?
      @active
    end

    def finish
      @active = false
      @finish_count += 1
    end
  end

  if Object.const_defined?(:Mackerel)
    class Transport < ::Mackerel::NetHTTPTransport
      def initialize(http, mode = :production)
        @test_http = http
        super(ca_file: '/test/ca.pem', mode: mode)
      end

      private

      def new_http
        @test_http
      end
    end
  end

  def test_requires_ca_file_and_known_mode
    assert_raise(Mackerel::ConfigurationError) do
      Mackerel::NetHTTPTransport.new(ca_file: '', mode: :production)
    end
    assert_raise(Mackerel::ConfigurationError) do
      Mackerel::NetHTTPTransport.new(ca_file: '/test/ca.pem', mode: :unsafe)
    end
  end

  def test_production_fails_when_http_boundaries_are_missing
    assert_raise(Mackerel::UnsupportedTransportError) do
      Mackerel::NetHTTPTransport.new(ca_file: '/test/ca.pem', mode: :production)
    end
  end

  def test_production_sets_tls_deadlines_and_limits
    http = HTTP.new
    response = Transport.new(http).post(path: '/path', headers: {'X-Test' => 'yes'}, body: '[]')

    assert_equal(200, response.status_code)
    assert_equal('application/json', response.headers['content-type'])
    assert_equal('/test/ca.pem', http.ca_file)
    assert_equal(10, http.open_timeout)
    assert_equal(10, http.read_timeout)
    assert_equal(10, http.write_timeout)
    assert_equal(30, http.total_timeout)
    assert_equal(2_048, http.max_request_bytes)
    assert_equal(4_096, http.max_response_header_bytes)
    assert_equal(4_096, http.max_response_body_bytes)
    assert_equal(1_024, http.max_response_line_bytes)
    assert_equal(1, http.posts.length)
    assert_equal(1, http.finish_count)
  end

  def test_connect_failure_is_not_sent_and_redacted
    http = HTTP.new
    http.fail_start
    error = nil
    begin
      Transport.new(http, :compat).post(path: '/path', headers: {}, body: '[]')
    rescue Mackerel::TransportFailure => failure
      error = failure
    end

    assert_equal(:before_request, error.phase)
    assert_equal(:connect_failed, error.reason)
    assert_false(error.retryable)
    assert_false(error.to_s.include?('secret'))
  end

  def test_request_failure_is_unknown_and_closes
    http = HTTP.new
    http.fail_post
    error = nil
    begin
      Transport.new(http, :compat).post(path: '/path', headers: {}, body: '[]')
    rescue Mackerel::TransportFailure => failure
      error = failure
    end

    assert_equal(:request_started, error.phase)
    assert_equal(:request_failed, error.reason)
    assert(error.retryable)
    assert_equal(1, http.finish_count)
    assert_false(error.to_s.include?('secret'))
  end

  def test_inspect_does_not_include_ca_path
    transport = Transport.new(HTTP.new, :compat)
    assert_false(transport.inspect.include?('/test/ca.pem'))
  end
end
