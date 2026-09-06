# picoruby-mackerel

A small mrbgem that sends PicoRuby metrics to a Mackerel service or an existing host with a single synchronous HTTPS POST.

## Scope

- PicoRuby / mruby VM
- Reference PicoRuby commit: `c9681b351c651016937830c810837877d232317e`
- 1–8 metrics per batch
- Service metrics: `POST /api/v0/services/<service>/tsdb`
- Host metrics: `POST /api/v0/tsdb`

This gem does not provide automatic retries, a persistent queue, time synchronization, Wi-Fi reconnection, or sensor drivers. Unsent batches are lost on power failure, and retrying a POST after losing its response may create duplicates.

The current Mackerel API accepts JSON fields named `name`, `time`, and `value` for both service and host metrics, and returns `{"success":true}` on success. Host metrics also require `hostId`. The API key needs Read/Write permission. Check the official documentation for current pricing, limits, permissions, and accepted timestamp ranges before deployment.

- [Mackerel API overview](https://mackerel.io/api-docs/)
- [Service metrics](https://mackerel.io/api-docs/entry/service-metrics)
- [Host metrics](https://mackerel.io/api-docs/entry/host-metrics)

## Integration

Place PicoRuby and this repository in sibling directories, then add the gem inside the build block of the target build config:

```ruby
conf.gem File.expand_path('../../picoruby-mackerel', __dir__)
```

## Usage

Set `ready?` to true only after setting both the system clock and the C-level clock used by TLS. Provision the API key separately; do not embed it in source code or publicly distributed firmware.

```ruby
require 'mackerel'

transport = Mackerel::NetHTTPTransport.new(
  ca_file: '/path/to/managed-ca.pem',
  mode: :production
)

client = Mackerel::Client.new(
  api_key: provisioned_api_key,
  service: 'picoruby-sensors',
  clock: board_clock,
  transport: transport
)

measured_at = board_clock.unix_seconds
result = client.post([
  {
    'name' => 'custom.sensor.pico2w01.temperature_c',
    'time' => measured_at,
    'value' => temperature_c
  }
])
```

`Result` provides `success?`, `retryable?`, `http_status`, `error_code`, `delivery`, and `retry_after_seconds`. Log only the fixed `error_code` and status; never log the API key or request body.

## Transport modes

`production` starts only when `picoruby-net-http` provides effective `open_timeout`, `read_timeout`, `write_timeout`, and `total_timeout` controls plus request and response size limits. The reference PicoRuby commit lacks the latter APIs, so initialization raises `UnsupportedTransportError`. This production gate prevents silently ignored configuration.

`compat` uses the reference PicoRuby HTTPS implementation for connectivity checks. CA and peer verification remain mandatory, but this mode is not for production because it cannot guarantee a total deadline, an in-flight response size limit, or complete HTTP framing.

## Testing

Create a symlink from the PicoRuby checkout's `mrbgems/picoruby-mackerel` directory to this repository, then run:

```sh
bundle exec rake 'test:gems:picoruby[picoruby-mackerel]'
```

See [qualification.md](docs/qualification.md) for the tested and untested scope.
