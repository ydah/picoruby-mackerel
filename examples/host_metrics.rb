require 'mackerel'

def mackerel_host_client(api_key, ca_file, clock, host_id)
  Mackerel::Client.new(
    api_key: api_key,
    host_id: host_id,
    clock: clock,
    transport: Mackerel::NetHTTPTransport.new(ca_file: ca_file, mode: :production)
  )
end

def post_humidity(client, clock, humidity_pct)
  client.post([
    {
      'name' => 'custom.sensor.pico2w01.humidity_pct',
      'time' => clock.unix_seconds,
      'value' => humidity_pct
    }
  ])
end

