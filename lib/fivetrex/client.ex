defmodule Fivetrex.Client do
  @moduledoc """
  Low-level HTTP client for the Fivetran REST API.

  This module handles authentication, request building, and response parsing.
  It is used internally by the API modules (`Fivetrex.Groups`, `Fivetrex.Connectors`,
  etc.) and is not typically used directly.

  ## Authentication

  The client uses HTTP Basic Authentication with your Fivetran API key and secret.
  Credentials are Base64-encoded and sent in the `Authorization` header with each request.

  ## Creating a Client

  Use `Fivetrex.client/1` to create a new client instance:

      client = Fivetrex.client(
        api_key: "your_api_key",
        api_secret: "your_api_secret"
      )

  ## Request Methods

  The client provides methods for each HTTP verb:

    * `get/3` - GET requests with optional query parameters
    * `post/3` - POST requests with JSON body
    * `patch/3` - PATCH requests with JSON body
    * `delete/2` - DELETE requests

  ## Response Handling

  All request methods return `{:ok, body}` on success (2xx status) or
  `{:error, %Fivetrex.Error{}}` on failure. The response body is automatically
  decoded from JSON.

  ## Error Mapping

  HTTP errors are mapped to structured `Fivetrex.Error` types:

    * 401 → `:unauthorized`
    * 404 → `:not_found`
    * 429 → `:rate_limited` (includes `retry_after` from header)
    * 5xx → `:server_error`
    * Other → `:unknown`
  """

  @default_base_url "https://api.fivetran.com/v1"

  @typedoc """
  A Fivetrex client struct containing the configured Req request.

  This struct is opaque and should be created using `Fivetrex.client/1`.
  """
  @type t :: %__MODULE__{
          req: Req.Request.t()
        }

  defstruct [:req]

  @doc """
  Creates a new client with the given options.

  This function is called internally by `Fivetrex.client/1`. Prefer using
  that function for creating clients.

  ## Options

    * `:api_key` - Required. Your Fivetran API key.
    * `:api_secret` - Required. Your Fivetran API secret.
    * `:base_url` - Optional. Override the API base URL. Defaults to
      `#{@default_base_url}`.

  ## Examples

      client = Fivetrex.Client.new(
        api_key: "key",
        api_secret: "secret"
      )

  """
  @spec new(keyword()) :: t()
  def new(opts) do
    api_key = Keyword.fetch!(opts, :api_key)
    api_secret = Keyword.fetch!(opts, :api_secret)
    base_url = Keyword.get(opts, :base_url, @default_base_url)

    auth = Base.encode64("#{api_key}:#{api_secret}")

    req =
      Req.new(
        base_url: base_url,
        headers: [
          {"authorization", "Basic #{auth}"},
          {"content-type", "application/json"}
        ],
        # Disable automatic retry - we handle errors explicitly
        retry: false
      )

    %__MODULE__{req: req}
  end

  @doc """
  Performs a GET request to the specified path.

  ## Parameters

    * `client` - The Fivetrex client
    * `path` - The API path (e.g., "/groups" or "/connectors/abc123")
    * `opts` - Optional keyword list:
      * `:params` - Query parameters as a keyword list or map

  ## Examples

      # Simple GET
      {:ok, body} = Fivetrex.Client.get(client, "/groups")

      # GET with query parameters
      {:ok, body} = Fivetrex.Client.get(client, "/groups", params: [limit: 10])

  ## Returns

    * `{:ok, map()}` - The decoded JSON response body
    * `{:error, Fivetrex.Error.t()}` - A structured error

  """
  @spec get(t(), String.t(), keyword()) :: {:ok, map()} | {:error, Fivetrex.Error.t()}
  def get(%__MODULE__{req: req}, path, opts \\ []) do
    params = Keyword.get(opts, :params, [])

    req
    |> Req.get(url: path, params: params)
    |> handle_response()
  end

  @doc """
  Performs a POST request to the specified path with a JSON body.

  ## Parameters

    * `client` - The Fivetrex client
    * `path` - The API path
    * `body` - The request body (will be JSON-encoded)

  ## Examples

      {:ok, body} = Fivetrex.Client.post(client, "/groups", %{name: "My Group"})

  ## Returns

    * `{:ok, map()}` - The decoded JSON response body
    * `{:error, Fivetrex.Error.t()}` - A structured error

  """
  @spec post(t(), String.t(), map()) :: {:ok, map()} | {:error, Fivetrex.Error.t()}
  def post(%__MODULE__{req: req}, path, body \\ %{}) do
    req
    |> Req.post(url: path, json: body)
    |> handle_response()
  end

  @doc """
  Performs a PATCH request to the specified path with a JSON body.

  ## Parameters

    * `client` - The Fivetrex client
    * `path` - The API path
    * `body` - The request body (will be JSON-encoded)

  ## Examples

      {:ok, body} = Fivetrex.Client.patch(client, "/groups/abc", %{name: "New Name"})

  ## Returns

    * `{:ok, map()}` - The decoded JSON response body
    * `{:error, Fivetrex.Error.t()}` - A structured error

  """
  @spec patch(t(), String.t(), map()) :: {:ok, map()} | {:error, Fivetrex.Error.t()}
  def patch(%__MODULE__{req: req}, path, body) do
    req
    |> Req.patch(url: path, json: body)
    |> handle_response()
  end

  @doc """
  Performs a DELETE request to the specified path.

  ## Parameters

    * `client` - The Fivetrex client
    * `path` - The API path

  ## Examples

      {:ok, _} = Fivetrex.Client.delete(client, "/groups/abc")

  ## Returns

    * `{:ok, map()}` - The decoded JSON response body (usually empty)
    * `{:error, Fivetrex.Error.t()}` - A structured error

  """
  @spec delete(t(), String.t()) :: {:ok, map()} | {:error, Fivetrex.Error.t()}
  def delete(%__MODULE__{req: req}, path) do
    req
    |> Req.delete(url: path)
    |> handle_response()
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}})
       when status in 200..299 do
    {:ok, body}
  end

  defp handle_response({:ok, %Req.Response{status: 401, body: body}}) do
    message = get_message(body) || "Unauthorized"
    {:error, Fivetrex.Error.unauthorized(message)}
  end

  defp handle_response({:ok, %Req.Response{status: 404, body: body}}) do
    message = get_message(body) || "Not found"
    {:error, Fivetrex.Error.not_found(message)}
  end

  defp handle_response({:ok, %Req.Response{status: 429, body: body, headers: headers}}) do
    message = get_message(body) || "Rate limited"
    retry_after = get_retry_after(headers)
    {:error, Fivetrex.Error.rate_limited(message, retry_after)}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}})
       when status >= 500 do
    message = get_message(body) || "Server error"
    {:error, Fivetrex.Error.server_error(message, status)}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    message = get_message(body) || "Request failed"
    {:error, Fivetrex.Error.unknown(message, status)}
  end

  defp handle_response({:error, exception}) do
    {:error, Fivetrex.Error.unknown(Exception.message(exception), nil)}
  end

  defp get_message(body) when is_map(body), do: body["message"]
  defp get_message(_body), do: nil

  defp get_retry_after(headers) when is_map(headers) do
    case Map.get(headers, "retry-after") do
      [value | _] -> String.to_integer(value)
      value when is_binary(value) -> String.to_integer(value)
      _ -> nil
    end
  end

  defp get_retry_after(_headers), do: nil
end
