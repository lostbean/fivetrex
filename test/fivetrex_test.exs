defmodule FivetrexTest do
  use ExUnit.Case

  alias Fivetrex.Error

  describe "client/1" do
    test "creates a client" do
      client = Fivetrex.client(api_key: "key", api_secret: "secret")
      assert %Fivetrex.Client{} = client
    end
  end

  describe "with_retry/2" do
    test "returns success immediately without retry" do
      result = Fivetrex.with_retry(fn -> {:ok, "success"} end)
      assert result == {:ok, "success"}
    end

    test "retries on rate_limited error" do
      call_count = :counters.new(1, [:atomics])

      result =
        Fivetrex.with_retry(
          fn ->
            :counters.add(call_count, 1, 1)
            count = :counters.get(call_count, 1)

            if count < 2 do
              {:error, Error.rate_limited("Rate limit", nil)}
            else
              {:ok, "success after retry"}
            end
          end,
          base_delay_ms: 1
        )

      assert result == {:ok, "success after retry"}
      assert :counters.get(call_count, 1) == 2
    end

    test "does not retry on unauthorized error" do
      call_count = :counters.new(1, [:atomics])

      result =
        Fivetrex.with_retry(
          fn ->
            :counters.add(call_count, 1, 1)
            {:error, Error.unauthorized("Invalid credentials")}
          end,
          base_delay_ms: 1
        )

      assert {:error, %Error{type: :unauthorized}} = result
      assert :counters.get(call_count, 1) == 1
    end

    test "accepts custom options" do
      call_count = :counters.new(1, [:atomics])

      result =
        Fivetrex.with_retry(
          fn ->
            :counters.add(call_count, 1, 1)
            {:error, Error.server_error("Server error", 500)}
          end,
          max_attempts: 2,
          base_delay_ms: 1
        )

      assert {:error, %Error{type: :server_error}} = result
      assert :counters.get(call_count, 1) == 2
    end
  end
end
