defmodule Fivetrex.Retry do
  @moduledoc """
  Retry utilities with exponential backoff for handling transient failures.

  This module provides retry logic for Fivetran API calls that may fail due to
  rate limiting, temporary server errors, or network issues. It implements
  exponential backoff with optional jitter to prevent thundering herd problems.

  ## Quick Start

      # Retry with defaults (3 attempts, exponential backoff)
      {:ok, groups} = Fivetrex.Retry.with_backoff(fn ->
        Fivetrex.Groups.list(client)
      end)

      # Custom retry configuration
      {:ok, connector} = Fivetrex.Retry.with_backoff(
        fn -> Fivetrex.Connectors.get(client, connector_id) end,
        max_attempts: 5,
        base_delay_ms: 500,
        max_delay_ms: 30_000
      )

  ## How It Works

  1. Executes the provided function
  2. If successful, returns the result immediately
  3. If it fails with a retryable error, waits with exponential backoff
  4. Repeats until success or max attempts reached

  ## Retryable Errors

  By default, these error types are retried:
    * `:rate_limited` - Respects `retry_after` header when available
    * `:server_error` - 5xx errors are typically transient

  Non-retryable errors (returned immediately):
    * `:unauthorized` - Invalid credentials won't become valid
    * `:not_found` - Resource doesn't exist
    * `:unknown` - Unexpected errors need investigation

  ## Exponential Backoff

  Delays increase exponentially: `base_delay * 2^attempt`

  With default settings (base_delay: 1000ms):
    * Attempt 1 fails → wait ~1 second
    * Attempt 2 fails → wait ~2 seconds
    * Attempt 3 fails → wait ~4 seconds
    * (capped at max_delay)

  ## Jitter

  Optional random jitter prevents synchronized retries when multiple clients
  hit rate limits simultaneously:

      Fivetrex.Retry.with_backoff(func, jitter: true)

  ## Examples

  ### Basic Usage

      case Fivetrex.Retry.with_backoff(fn -> Fivetrex.Groups.list(client) end) do
        {:ok, %{items: groups}} ->
          process_groups(groups)

        {:error, error} ->
          # All retries exhausted
          Logger.error("Failed after retries: \#{error.message}")
      end

  ### With Rate Limit Handling

      # Respects Fivetran's retry-after header automatically
      {:ok, _} = Fivetrex.Retry.with_backoff(fn ->
        Fivetrex.Connectors.sync(client, connector_id)
      end)

  ### Custom Retry Predicate

      # Only retry on specific errors
      Fivetrex.Retry.with_backoff(
        fn -> Fivetrex.Connectors.get(client, id) end,
        retry_if: fn
          %Fivetrex.Error{type: :rate_limited} -> true
          _ -> false
        end
      )

  ### Fire and Forget with Logging

      Fivetrex.Retry.with_backoff(
        fn -> Fivetrex.Connectors.sync(client, connector_id) end,
        on_retry: fn error, attempt, delay ->
          Logger.warn("Retry \#{attempt}: \#{error.message}, waiting \#{delay}ms")
        end
      )

  """

  alias Fivetrex.Error

  @default_max_attempts 3
  @default_base_delay_ms 1_000
  @default_max_delay_ms 30_000

  @typedoc """
  Options for configuring retry behavior.

    * `:max_attempts` - Maximum number of attempts (default: 3)
    * `:base_delay_ms` - Initial delay in milliseconds (default: 1000)
    * `:max_delay_ms` - Maximum delay cap in milliseconds (default: 30000)
    * `:jitter` - Add random jitter to delays (default: false)
    * `:retry_if` - Custom function to determine if error is retryable
    * `:on_retry` - Callback function called before each retry
  """
  @type retry_opts :: [
          max_attempts: pos_integer(),
          base_delay_ms: pos_integer(),
          max_delay_ms: pos_integer(),
          jitter: boolean(),
          retry_if: (Error.t() -> boolean()),
          on_retry: (Error.t(), pos_integer(), pos_integer() -> any())
        ]

  @doc """
  Executes a function with automatic retry and exponential backoff.

  ## Parameters

    * `func` - A zero-arity function that returns `{:ok, result}` or `{:error, %Fivetrex.Error{}}`
    * `opts` - Optional keyword list (see module docs for options)

  ## Returns

    * `{:ok, result}` - The successful result from `func`
    * `{:error, %Fivetrex.Error{}}` - The last error after all retries exhausted

  ## Examples

      # Simple usage
      {:ok, groups} = Fivetrex.Retry.with_backoff(fn ->
        Fivetrex.Groups.list(client)
      end)

      # With options
      {:ok, connector} = Fivetrex.Retry.with_backoff(
        fn -> Fivetrex.Connectors.get(client, id) end,
        max_attempts: 5,
        jitter: true
      )

  """
  @spec with_backoff((-> {:ok, any()} | {:error, Error.t()}), retry_opts()) ::
          {:ok, any()} | {:error, Error.t()}
  def with_backoff(func, opts \\ []) when is_function(func, 0) do
    max_attempts = Keyword.get(opts, :max_attempts, @default_max_attempts)
    base_delay_ms = Keyword.get(opts, :base_delay_ms, @default_base_delay_ms)
    max_delay_ms = Keyword.get(opts, :max_delay_ms, @default_max_delay_ms)
    jitter = Keyword.get(opts, :jitter, false)
    retry_if = Keyword.get(opts, :retry_if, &default_retry_predicate/1)
    on_retry = Keyword.get(opts, :on_retry, fn _, _, _ -> :ok end)

    do_retry(func, 1, max_attempts, base_delay_ms, max_delay_ms, jitter, retry_if, on_retry)
  end

  defp do_retry(
         func,
         attempt,
         max_attempts,
         base_delay_ms,
         max_delay_ms,
         jitter,
         retry_if,
         on_retry
       ) do
    case func.() do
      {:ok, _} = success ->
        success

      {:error, %Error{} = error} = failure ->
        cond do
          attempt >= max_attempts ->
            failure

          not retry_if.(error) ->
            failure

          true ->
            delay = calculate_delay(error, attempt, base_delay_ms, max_delay_ms, jitter)
            on_retry.(error, attempt, delay)
            Process.sleep(delay)

            do_retry(
              func,
              attempt + 1,
              max_attempts,
              base_delay_ms,
              max_delay_ms,
              jitter,
              retry_if,
              on_retry
            )
        end
    end
  end

  @doc """
  The default retry predicate - determines which errors are retryable.

  Returns `true` for:
    * `:rate_limited` - API rate limits are transient
    * `:server_error` - 5xx errors are typically transient

  Returns `false` for:
    * `:unauthorized` - Invalid credentials
    * `:not_found` - Resource doesn't exist
    * `:unknown` - Unexpected errors

  ## Examples

      iex> Fivetrex.Retry.default_retry_predicate(%Fivetrex.Error{type: :rate_limited})
      true

      iex> Fivetrex.Retry.default_retry_predicate(%Fivetrex.Error{type: :not_found})
      false

  """
  @spec default_retry_predicate(Error.t()) :: boolean()
  def default_retry_predicate(%Error{type: type}) do
    type in [:rate_limited, :server_error]
  end

  @doc """
  Calculates the delay before the next retry attempt.

  For rate-limited errors with a `retry_after` value, uses that directly.
  Otherwise, uses exponential backoff: `base_delay * 2^(attempt-1)`

  ## Parameters

    * `error` - The error that triggered the retry
    * `attempt` - The current attempt number (1-based)
    * `base_delay_ms` - Base delay in milliseconds
    * `max_delay_ms` - Maximum delay cap
    * `jitter` - Whether to add random jitter

  ## Examples

      iex> error = %Fivetrex.Error{type: :server_error, retry_after: nil}
      iex> Fivetrex.Retry.calculate_delay(error, 1, 1000, 30000, false)
      1000

      iex> error = %Fivetrex.Error{type: :server_error, retry_after: nil}
      iex> Fivetrex.Retry.calculate_delay(error, 3, 1000, 30000, false)
      4000

      iex> error = %Fivetrex.Error{type: :rate_limited, retry_after: 60}
      iex> Fivetrex.Retry.calculate_delay(error, 1, 1000, 30000, false)
      60000

  """
  @spec calculate_delay(Error.t(), pos_integer(), pos_integer(), pos_integer(), boolean()) ::
          pos_integer()
  def calculate_delay(
        %Error{type: :rate_limited, retry_after: retry_after},
        _attempt,
        _base,
        max_delay_ms,
        jitter
      )
      when is_integer(retry_after) and retry_after > 0 do
    # Use the server-provided retry-after value (convert seconds to ms)
    delay = retry_after * 1000
    delay = min(delay, max_delay_ms)
    maybe_add_jitter(delay, jitter)
  end

  def calculate_delay(_error, attempt, base_delay_ms, max_delay_ms, jitter) do
    # Exponential backoff: base * 2^(attempt-1)
    exponent = attempt - 1
    delay = base_delay_ms * Integer.pow(2, exponent)
    delay = min(delay, max_delay_ms)
    maybe_add_jitter(delay, jitter)
  end

  defp maybe_add_jitter(delay, false), do: delay

  defp maybe_add_jitter(delay, true) do
    # Add up to 25% random jitter
    jitter_range = div(delay, 4)
    delay + :rand.uniform(max(jitter_range, 1))
  end
end
