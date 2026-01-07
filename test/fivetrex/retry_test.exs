defmodule Fivetrex.RetryTest do
  use ExUnit.Case, async: true

  alias Fivetrex.Error
  alias Fivetrex.Retry

  describe "with_backoff/2" do
    test "returns success immediately without retry" do
      call_count = :counters.new(1, [:atomics])

      result =
        Retry.with_backoff(fn ->
          :counters.add(call_count, 1, 1)
          {:ok, "success"}
        end)

      assert result == {:ok, "success"}
      assert :counters.get(call_count, 1) == 1
    end

    test "retries on rate_limited error" do
      call_count = :counters.new(1, [:atomics])

      result =
        Retry.with_backoff(
          fn ->
            :counters.add(call_count, 1, 1)
            count = :counters.get(call_count, 1)

            if count < 3 do
              {:error, Error.rate_limited("Rate limit", nil)}
            else
              {:ok, "success after retry"}
            end
          end,
          base_delay_ms: 1,
          max_attempts: 5
        )

      assert result == {:ok, "success after retry"}
      assert :counters.get(call_count, 1) == 3
    end

    test "retries on server_error" do
      call_count = :counters.new(1, [:atomics])

      result =
        Retry.with_backoff(
          fn ->
            :counters.add(call_count, 1, 1)
            count = :counters.get(call_count, 1)

            if count < 2 do
              {:error, Error.server_error("Server error", 500)}
            else
              {:ok, "recovered"}
            end
          end,
          base_delay_ms: 1
        )

      assert result == {:ok, "recovered"}
      assert :counters.get(call_count, 1) == 2
    end

    test "does not retry on unauthorized error" do
      call_count = :counters.new(1, [:atomics])

      result =
        Retry.with_backoff(
          fn ->
            :counters.add(call_count, 1, 1)
            {:error, Error.unauthorized("Invalid credentials")}
          end,
          base_delay_ms: 1
        )

      assert {:error, %Error{type: :unauthorized}} = result
      assert :counters.get(call_count, 1) == 1
    end

    test "does not retry on not_found error" do
      call_count = :counters.new(1, [:atomics])

      result =
        Retry.with_backoff(
          fn ->
            :counters.add(call_count, 1, 1)
            {:error, Error.not_found("Resource not found")}
          end,
          base_delay_ms: 1
        )

      assert {:error, %Error{type: :not_found}} = result
      assert :counters.get(call_count, 1) == 1
    end

    test "does not retry on unknown error" do
      call_count = :counters.new(1, [:atomics])

      result =
        Retry.with_backoff(
          fn ->
            :counters.add(call_count, 1, 1)
            {:error, Error.unknown("Unknown error", 418)}
          end,
          base_delay_ms: 1
        )

      assert {:error, %Error{type: :unknown}} = result
      assert :counters.get(call_count, 1) == 1
    end

    test "stops after max_attempts" do
      call_count = :counters.new(1, [:atomics])

      result =
        Retry.with_backoff(
          fn ->
            :counters.add(call_count, 1, 1)
            {:error, Error.rate_limited("Always failing", nil)}
          end,
          max_attempts: 3,
          base_delay_ms: 1
        )

      assert {:error, %Error{type: :rate_limited}} = result
      assert :counters.get(call_count, 1) == 3
    end

    test "calls on_retry callback before each retry" do
      retry_log = :ets.new(:retry_log, [:bag, :public])

      result =
        Retry.with_backoff(
          fn ->
            {:error, Error.server_error("Failing", 503)}
          end,
          max_attempts: 3,
          base_delay_ms: 1,
          on_retry: fn error, attempt, delay ->
            :ets.insert(retry_log, {attempt, error.type, delay})
          end
        )

      assert {:error, _} = result

      # Should have 2 retry callbacks (attempts 1 and 2, not 3 since that's the final failure)
      entries = :ets.tab2list(retry_log)
      assert length(entries) == 2

      assert Enum.any?(entries, fn {attempt, type, _} ->
               attempt == 1 and type == :server_error
             end)

      assert Enum.any?(entries, fn {attempt, type, _} ->
               attempt == 2 and type == :server_error
             end)

      :ets.delete(retry_log)
    end

    test "uses custom retry_if predicate" do
      call_count = :counters.new(1, [:atomics])

      # Custom predicate: only retry on unknown errors (opposite of default)
      result =
        Retry.with_backoff(
          fn ->
            :counters.add(call_count, 1, 1)
            count = :counters.get(call_count, 1)

            if count < 2 do
              {:error, Error.unknown("Custom retryable", 418)}
            else
              {:ok, "success"}
            end
          end,
          base_delay_ms: 1,
          retry_if: fn error -> error.type == :unknown end
        )

      assert result == {:ok, "success"}
      assert :counters.get(call_count, 1) == 2
    end
  end

  describe "default_retry_predicate/1" do
    test "returns true for rate_limited" do
      assert Retry.default_retry_predicate(%Error{type: :rate_limited})
    end

    test "returns true for server_error" do
      assert Retry.default_retry_predicate(%Error{type: :server_error})
    end

    test "returns false for unauthorized" do
      refute Retry.default_retry_predicate(%Error{type: :unauthorized})
    end

    test "returns false for not_found" do
      refute Retry.default_retry_predicate(%Error{type: :not_found})
    end

    test "returns false for unknown" do
      refute Retry.default_retry_predicate(%Error{type: :unknown})
    end
  end

  describe "calculate_delay/5" do
    test "uses retry_after for rate_limited errors" do
      error = %Error{type: :rate_limited, message: "Rate limited", status: 429, retry_after: 60}
      delay = Retry.calculate_delay(error, 1, 1000, 120_000, false)

      # 60 seconds = 60000 ms
      assert delay == 60_000
    end

    test "caps retry_after at max_delay" do
      error = %Error{type: :rate_limited, message: "Rate limited", status: 429, retry_after: 300}
      delay = Retry.calculate_delay(error, 1, 1000, 30_000, false)

      assert delay == 30_000
    end

    test "uses exponential backoff for other errors" do
      error = %Error{type: :server_error, message: "Server error", status: 500, retry_after: nil}

      # Attempt 1: base * 2^0 = 1000
      assert Retry.calculate_delay(error, 1, 1000, 30_000, false) == 1000

      # Attempt 2: base * 2^1 = 2000
      assert Retry.calculate_delay(error, 2, 1000, 30_000, false) == 2000

      # Attempt 3: base * 2^2 = 4000
      assert Retry.calculate_delay(error, 3, 1000, 30_000, false) == 4000

      # Attempt 4: base * 2^3 = 8000
      assert Retry.calculate_delay(error, 4, 1000, 30_000, false) == 8000
    end

    test "caps exponential backoff at max_delay" do
      error = %Error{type: :server_error, message: "Server error", status: 500, retry_after: nil}

      # Attempt 10: base * 2^9 = 512000, but capped at 30000
      delay = Retry.calculate_delay(error, 10, 1000, 30_000, false)
      assert delay == 30_000
    end

    test "adds jitter when enabled" do
      error = %Error{type: :server_error, message: "Server error", status: 500, retry_after: nil}

      # Run multiple times to verify jitter adds variability
      delays =
        for _ <- 1..10 do
          Retry.calculate_delay(error, 1, 1000, 30_000, true)
        end

      # With jitter, delays should be >= base delay
      assert Enum.all?(delays, &(&1 >= 1000))

      # With jitter (up to 25%), delays should be <= base * 1.25
      assert Enum.all?(delays, &(&1 <= 1250))

      # There should be some variation (not all the same)
      # Note: This could theoretically fail with very low probability
      unique_delays = Enum.uniq(delays)
      assert length(unique_delays) > 1
    end

    test "handles nil retry_after in rate_limited error" do
      error = %Error{type: :rate_limited, message: "Rate limited", status: 429, retry_after: nil}

      # Should fall back to exponential backoff
      delay = Retry.calculate_delay(error, 2, 1000, 30_000, false)
      assert delay == 2000
    end
  end

  describe "integration scenarios" do
    test "handles rapid succession of transient failures" do
      call_count = :counters.new(1, [:atomics])

      result =
        Retry.with_backoff(
          fn ->
            :counters.add(call_count, 1, 1)
            count = :counters.get(call_count, 1)

            case count do
              1 -> {:error, Error.server_error("503", 503)}
              2 -> {:error, Error.server_error("502", 502)}
              3 -> {:error, Error.rate_limited("Rate limit", 1)}
              _ -> {:ok, "finally"}
            end
          end,
          max_attempts: 5,
          base_delay_ms: 1
        )

      assert result == {:ok, "finally"}
      assert :counters.get(call_count, 1) == 4
    end

    test "respects rate_limited retry_after in delay calculation" do
      start_time = System.monotonic_time(:millisecond)

      # Use a very short retry_after for testing
      Retry.with_backoff(
        fn ->
          {:error, Error.rate_limited("Rate limited", 1)}
        end,
        max_attempts: 2,
        base_delay_ms: 10,
        max_delay_ms: 5000
      )

      end_time = System.monotonic_time(:millisecond)
      elapsed = end_time - start_time

      # Should wait at least 1000ms (1 second from retry_after)
      # But allow some tolerance for test execution
      assert elapsed >= 900
    end
  end
end
