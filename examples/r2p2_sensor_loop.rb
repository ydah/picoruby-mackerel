require 'mackerel'

INTERVAL_MS = 60_000
MAX_ATTEMPTS = 3
MAX_AGE_MS = 300_000

# clock_ms, sleep_ms and measure are callables supplied by the application.
def run_sensor_loop(client, clock, clock_ms, sleep_ms, measure)
  pending = nil
  attempts = 0
  created_at = 0
  retry_at = 0
  rate_limit_until = 0
  next_measurement = clock_ms.call

  loop do
    now = clock_ms.call
    if now >= next_measurement
      if pending.nil? && clock.ready?
        pending = measure.call(clock.unix_seconds)
        created_at = now if pending
      end
      next_measurement += INTERVAL_MS
    end

    if pending && now - created_at > MAX_AGE_MS
      pending = nil
      attempts = 0
    elsif pending && now >= retry_at && now >= rate_limit_until
      attempts += 1
      result = client.post(pending)
      return result unless result.success? || result.retryable?
      if result.success? || attempts >= MAX_ATTEMPTS
        pending = nil
        attempts = 0
      else
        delay = (2 ** (attempts - 1)) * 1_000 + rand(1_000)
        delay = result.retry_after_seconds * 1_000 if result.retry_after_seconds
        retry_at = now + delay
        rate_limit_until = retry_at if result.error_code == :rate_limited
      end
    end
    sleep_ms.call(100)
  end
end
