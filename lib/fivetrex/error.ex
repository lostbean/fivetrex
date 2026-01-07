defmodule Fivetrex.Error do
  @moduledoc """
  Structured error types for Fivetran API responses.

  All API functions in Fivetrex return `{:error, %Fivetrex.Error{}}` on failure.
  This struct provides structured information about what went wrong, making it
  easy to pattern match on error types and handle them appropriately.

  ## Error Types

  The `:type` field indicates the category of error:

    * `:unauthorized` - Invalid or missing API credentials (HTTP 401)
    * `:not_found` - The requested resource does not exist (HTTP 404)
    * `:rate_limited` - Too many requests; check `:retry_after` (HTTP 429)
    * `:server_error` - Fivetran server error (HTTP 5xx)
    * `:unknown` - Unexpected or unclassified error

  ## Fields

    * `:type` - The error category (see above)
    * `:message` - Human-readable error message from Fivetran
    * `:status` - The HTTP status code (if applicable)
    * `:retry_after` - Seconds to wait before retrying (for `:rate_limited` errors)

  ## Examples

  Pattern matching on error types:

      case Fivetrex.Connectors.get(client, "invalid_id") do
        {:ok, connector} ->
          # Handle success
          connector

        {:error, %Fivetrex.Error{type: :not_found}} ->
          # Resource doesn't exist
          nil

        {:error, %Fivetrex.Error{type: :unauthorized}} ->
          # Invalid credentials - re-authenticate
          raise "Invalid API credentials"

        {:error, %Fivetrex.Error{type: :rate_limited, retry_after: seconds}} ->
          # Wait and retry
          Process.sleep(seconds * 1000)
          Fivetrex.Connectors.get(client, "invalid_id")

        {:error, %Fivetrex.Error{type: :server_error, status: status}} ->
          # Log and maybe retry
          Logger.error("Fivetran server error: \#{status}")
          {:error, :server_error}

        {:error, %Fivetrex.Error{message: message}} ->
          # Catch-all for other errors
          {:error, message}
      end

  ## Exception Behavior

  `Fivetrex.Error` implements the `Exception` behaviour, so you can raise it:

      {:error, error} = Fivetrex.Connectors.get(client, "invalid")
      raise error
      # => ** (Fivetrex.Error) Resource not found

  """

  @typedoc """
  The category of error that occurred.

    * `:unauthorized` - Authentication failed (401)
    * `:not_found` - Resource not found (404)
    * `:rate_limited` - Rate limit exceeded (429)
    * `:server_error` - Server-side error (5xx)
    * `:unknown` - Unexpected error
  """
  @type error_type :: :unauthorized | :not_found | :rate_limited | :server_error | :unknown

  @typedoc """
  A structured Fivetran API error.

  See module documentation for field descriptions and usage examples.
  """
  @type t :: %__MODULE__{
          type: error_type(),
          message: String.t(),
          status: integer() | nil,
          retry_after: integer() | nil
        }

  defexception [:type, :message, :status, :retry_after]

  @doc """
  Returns the error message for exception handling.

  This is called automatically when the error is raised.
  """
  @impl true
  def message(%__MODULE__{message: message}), do: message

  @doc false
  @spec unauthorized(String.t()) :: t()
  def unauthorized(message) do
    %__MODULE__{type: :unauthorized, message: message, status: 401}
  end

  @doc false
  @spec not_found(String.t()) :: t()
  def not_found(message) do
    %__MODULE__{type: :not_found, message: message, status: 404}
  end

  @doc false
  @spec rate_limited(String.t(), integer() | nil) :: t()
  def rate_limited(message, retry_after) do
    %__MODULE__{type: :rate_limited, message: message, status: 429, retry_after: retry_after}
  end

  @doc false
  @spec server_error(String.t(), integer()) :: t()
  def server_error(message, status) do
    %__MODULE__{type: :server_error, message: message, status: status}
  end

  @doc false
  @spec unknown(String.t(), integer() | nil) :: t()
  def unknown(message, status) do
    %__MODULE__{type: :unknown, message: message, status: status}
  end
end
