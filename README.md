# picoruby-mackerel

A small Mackerel metrics client for PicoRuby that validates service or host metric batches before a single verified HTTPS POST.

- Posts 1–8 custom metrics per synchronous request
- Supports Mackerel service metrics and host metrics
- Validates destinations, metric names, timestamps, values, and request sizes before sending
- Reports success, retryability, and delivery certainty without exposing the API key

## Requirements

- PicoRuby / mruby (tested against PicoRuby commit `c9681b351c651016937830c810837877d232317e`)
- A Mackerel API key with Read/Write permission
- A managed CA certificate file
- An application clock with `ready?` and `unix_seconds`; both the system clock and the C-level clock used by TLS must be set before it reports ready

See [qualification.md](docs/qualification.md) for the exact tested and untested scope.

## Installation

Place PicoRuby and this repository in sibling directories, then add the gem to the target PicoRuby build config:

```ruby
conf.gem File.expand_path('../../picoruby-mackerel', __dir__)
```

The gem declares its `picoruby-net-http`, `picoruby-json`, and `picoruby-time` dependencies in [`mrbgem.rake`](mrbgem.rake).

## Quick start

The reference PicoRuby commit supports `:compat` mode for connectivity checks. It still verifies the TLS peer, but it is not production-safe; see [Transport modes](#transport-modes).

```ruby
require 'mackerel'

transport = Mackerel::NetHTTPTransport.new(
  ca_file: '/path/to/managed-ca.pem',
  mode: :compat
)

client = Mackerel::Client.new(
  api_key: provisioned_api_key,
  service: 'picoruby-sensors',
  clock: board_clock,
  transport: transport
)

result = client.post([
  {
    'name' => 'custom.sensor.pico2w01.temperature_c',
    'time' => board_clock.unix_seconds,
    'value' => temperature_c
  }
])
```

Provision the API key separately; do not embed it in source code or publicly distributed firmware. For host metrics, pass `host_id:` instead of `service:`. Exactly one destination is required.

More examples:

- [Service metrics](examples/service_metrics.rb)
- [Host metrics](examples/host_metrics.rb)
- [Sensor loop with bounded retries](examples/r2p2_sensor_loop.rb)

## Results

`Mackerel::Result` exposes `success?`, `retryable?`, `http_status`, `error_code`, `delivery`, and `retry_after_seconds`. Log only the fixed error code and status; never log the API key or request body.

Retry only when `retryable?` is true. A `delivery` value of `:unknown` means Mackerel may already have received the request, so retrying can create duplicate points.

## Transport modes

`:production` fails during initialization unless `picoruby-net-http` provides effective open, read, write, and total timeouts plus request and response size limits. The reference PicoRuby commit lacks those APIs. This gate prevents silently ignored production settings.

`:compat` uses the reference PicoRuby HTTPS implementation for connectivity checks. CA and peer verification remain mandatory, but the mode cannot guarantee a total deadline, an in-flight response size limit, or complete HTTP framing.

## Operational boundaries

- Metric names must begin with `custom.` and be unique within a batch.
- Timestamps must be no more than 300 seconds old or 5 seconds in the future according to the supplied clock.
- JSON bodies are limited to 1,536 bytes and complete HTTP requests to 2,048 bytes.
- Automatic retries, persistent queues, time synchronization, Wi-Fi reconnection, and sensor drivers are outside this gem.
- Unsent batches are lost on power failure.

The client targets Mackerel's [service metrics](https://mackerel.io/api-docs/entry/service-metrics) and [host metrics](https://mackerel.io/api-docs/entry/host-metrics) endpoints and expects a `{"success":true}` response. Consult the [Mackerel API documentation](https://mackerel.io/api-docs/) for service-side limits and behavior.

## Development

Symlink this repository to `mrbgems/picoruby-mackerel` in a PicoRuby checkout, then run:

```sh
bundle exec rake 'test:gems:picoruby[picoruby-mackerel]'
```

## License

[MIT](LICENSE)
