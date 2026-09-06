# Qualification

Last updated: 2026-09-06

## Environment

- PicoRuby commit: `c9681b351c651016937830c810837877d232317e`
- Local patches: none (integrated as a symlinked external mrbgem)
- VM: PicoRuby / mruby on a POSIX host
- Board: Raspberry Pi Pico 2 W (not tested)
- SDK commit: pinned checkout submodule `98a542c1a62fb549ffb5d66a3e5892b06276b670` (firmware not built)
- Host Ruby: 4.0.0
- Host TLS: Homebrew OpenSSL 3 (built with explicit include and library paths)
- Build profile / defines: PicoRuby gem-test host profile
- CA bundle source / fingerprint: not configured
- Firmware artifact / SHA-256: not created

## API specification check

The official Mackerel API documentation was checked on 2026-09-06:

- Base URL, JSON, and `X-Api-Key`: <https://mackerel.io/api-docs/>
- Service metrics endpoint, payload, 200 response, and 429 response: <https://mackerel.io/api-docs/entry/service-metrics>
- Host metrics endpoint, `hostId`, payload, and 200 response: <https://mackerel.io/api-docs/entry/host-metrics>

The official documentation states that the API key needs Read/Write permission and that metrics more than 24 hours old are not recorded even when the API returns 200. This client applies a stricter local limit of 300 seconds in the past.

## Evidence

| Test ID | Environment | Result | Evidence |
|---|---|---|---|
| C01–C16 | PicoRuby POSIX host | Pass | Picotest covers service and host metrics, input validation, clock validation, and input immutability |
| C17–C18 | PicoRuby POSIX host | Conditional | Implemented, but the current limits on other inputs make the boundary values unreachable |
| API response / Retry-After | PicoRuby POSIX host | Pass | Covers successful 200 responses, HTTP classification, delta-seconds, and oversized values |
| NetHTTPTransport unit | PicoRuby POSIX host / fake HTTP | Pass | Covers TLS settings, deadlines and limits, one POST, close behavior, failure phases, and secret redaction |
| Full gem suite | PicoRuby POSIX host | Pass | 133 assertions with 0 failures and 0 errors |
| T01–T09 | POSIX local TLS / Pico 2 W | Not tested | Test certificates and hardware are not prepared |
| H01–H18 | patched picoruby-net-http | Not tested | The reference PicoRuby commit lacks the production-boundary APIs |
| E01–E05 | Mackerel API / Pico 2 W | Not tested | No real API key or hardware was used |
| L01–L10 | Pico 2 W | Not tested | Fault-injection setup and hardware are not prepared |

## Resource measurements

- Baseline firmware size: not measured
- Candidate firmware size: not measured
- Heap after boot: not measured
- Peak heap during TLS handshake: not measured
- Heap after repeated close operations: not measured
- Long-run trend: not measured

## Limitations

- `mode: :production` requires `picoruby-net-http` with the transport-boundary APIs. It fails explicitly during initialization on the reference commit.
- `mode: :compat` is for connectivity checks and does not provide production guarantees for a total deadline, an in-flight response size limit, or complete HTTP framing.
- The reference PicoRuby version does not classify TLS and DNS failures with typed errors, so `compat` conservatively treats pre-connection failures as non-retryable.
- Pico 2 W, R2P2, mbedTLS, certificate-period validation, real Mackerel delivery, and 24-hour operation have not been tested.
- API keys, CA material, sensors, time sources, and Wi-Fi configuration are not included in this repository.
