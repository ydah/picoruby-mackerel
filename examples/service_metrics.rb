require 'mackerel'

def mackerel_service_client(api_key, ca_file, clock)
  Mackerel::Client.new(
    api_key: api_key,
    service: 'picoruby-sensors',
    clock: clock,
    transport: Mackerel::NetHTTPTransport.new(ca_file: ca_file, mode: :production)
  )
end

def post_temperature(client, clock, temperature_c)
  client.post([
    {
      'name' => 'custom.sensor.pico2w01.temperature_c',
      'time' => clock.unix_seconds,
      'value' => temperature_c
    }
  ])
end

