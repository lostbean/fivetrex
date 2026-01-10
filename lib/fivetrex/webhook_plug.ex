defmodule Fivetrex.WebhookPlug do
  @moduledoc """
  A Plug for handling incoming Fivetran webhooks in Phoenix/Bandit applications.

  This plug verifies webhook signatures and parses the payload into a
  `Fivetrex.Models.WebhookEvent` struct, making it easy to integrate Fivetran
  webhooks into your Phoenix application.

  ## Features

    * Verifies HMAC-SHA256 signatures to ensure requests are from Fivetran
    * Parses webhook payloads into typed structs
    * Returns appropriate HTTP error responses for invalid requests
    * Assigns the parsed event to the connection for downstream handlers

  ## Installation

  ### Step 1: Capture Raw Body

  This plug requires access to the raw request body for signature verification.
  Add a body reader to your endpoint:

      # In lib/my_app_web/endpoint.ex
      plug Plug.Parsers,
        parsers: [:urlencoded, :multipart, :json],
        pass: ["*/*"],
        body_reader: {Fivetrex.WebhookPlug, :cache_raw_body, []},  # Add this
        json_decoder: Phoenix.json_library()

  ### Step 2: Add Route

  Add a route for the webhook endpoint:

      # In lib/my_app_web/router.ex
      scope "/webhooks", MyAppWeb do
        pipe_through :api

        post "/fivetran", FivetranWebhookController, :receive
      end

  ### Step 3: Use the Plug

  Add the plug to your controller:

      defmodule MyAppWeb.FivetranWebhookController do
        use MyAppWeb, :controller

        plug Fivetrex.WebhookPlug,
          secret: {MyApp.Config, :fivetran_webhook_secret, []}
          # Or: secret: "my_static_secret"
          # Or: secret: {:system, "FIVETRAN_WEBHOOK_SECRET"}

        def receive(conn, _params) do
          event = conn.assigns.fivetran_event

          case event.event do
            "sync_end" ->
              # Handle sync completion
              handle_sync_end(event)

            "sync_start" ->
              # Handle sync start
              handle_sync_start(event)
          end

          json(conn, %{status: "ok"})
        end
      end

  ## Configuration Options

    * `:secret` - Required. The webhook secret for signature verification.
      Can be provided as:
      * A string: `secret: "my_secret"`
      * A tuple for runtime fetching: `secret: {Module, :function, args}`
      * A system env tuple: `secret: {:system, "ENV_VAR_NAME"}`

    * `:event_key` - Optional. The key to use in `conn.assigns` for the parsed
      event. Defaults to `:fivetran_event`.

    * `:on_error` - Optional. A function to customize error responses.
      Signature: `fn conn, error_type -> conn`. Defaults to sending JSON errors.

  ## Assigns

  On successful verification, this plug adds:

    * `conn.assigns.fivetran_event` - The `%Fivetrex.Models.WebhookEvent{}` struct
    * `conn.assigns.raw_body` - The raw request body (for debugging)

  ## Error Handling

  Invalid requests receive appropriate HTTP responses:

    * `400 Bad Request` - Missing signature header
    * `401 Unauthorized` - Invalid signature
    * `422 Unprocessable Entity` - Invalid JSON payload

  ## See Also

    * `Fivetrex.WebhookSignature` - Low-level signature verification
    * `Fivetrex.Models.WebhookEvent` - The event struct
    * `Fivetrex.Webhooks` - API for managing webhooks
  """

  @behaviour Plug

  import Plug.Conn

  alias Fivetrex.Models.WebhookEvent
  alias Fivetrex.WebhookSignature

  @impl true
  def init(opts) do
    secret = Keyword.fetch!(opts, :secret)
    event_key = Keyword.get(opts, :event_key, :fivetran_event)
    on_error = Keyword.get(opts, :on_error, &default_error_handler/2)

    %{
      secret: secret,
      event_key: event_key,
      on_error: on_error
    }
  end

  @impl true
  def call(conn, %{secret: secret_config, event_key: event_key, on_error: on_error}) do
    with {:ok, raw_body} <- get_raw_body(conn),
         {:ok, signature} <- get_signature(conn),
         secret = resolve_secret(secret_config),
         :ok <- WebhookSignature.verify(raw_body, signature, secret),
         {:ok, payload} <- decode_payload(raw_body) do
      event = WebhookEvent.from_map(payload)

      conn
      |> assign(:raw_body, raw_body)
      |> assign(event_key, event)
    else
      {:error, :missing_body} ->
        on_error.(conn, :missing_body)

      {:error, :missing_signature} ->
        on_error.(conn, :missing_signature)

      {:error, :invalid_signature} ->
        on_error.(conn, :invalid_signature)

      {:error, :invalid_json} ->
        on_error.(conn, :invalid_json)
    end
  end

  @doc """
  Custom body reader that caches the raw body for signature verification.

  Use this as the `:body_reader` option in `Plug.Parsers`:

      plug Plug.Parsers,
        parsers: [:json],
        body_reader: {Fivetrex.WebhookPlug, :cache_raw_body, []},
        json_decoder: Jason

  """
  @spec cache_raw_body(Plug.Conn.t(), keyword()) ::
          {:ok, binary(), Plug.Conn.t()} | {:more, binary(), Plug.Conn.t()}
  def cache_raw_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        conn = put_private(conn, :fivetrex_raw_body, body)
        {:ok, body, conn}

      {:more, partial, conn} ->
        # For large bodies, accumulate
        existing = conn.private[:fivetrex_raw_body] || ""
        conn = put_private(conn, :fivetrex_raw_body, existing <> partial)
        {:more, partial, conn}

      {:error, _} = error ->
        error
    end
  end

  # Private functions

  defp get_raw_body(conn) do
    case conn.private[:fivetrex_raw_body] do
      nil -> {:error, :missing_body}
      body -> {:ok, body}
    end
  end

  defp get_signature(conn) do
    case get_req_header(conn, WebhookSignature.signature_header()) do
      [signature | _] when signature != "" -> {:ok, signature}
      _ -> {:error, :missing_signature}
    end
  end

  defp resolve_secret(secret) when is_binary(secret), do: secret

  defp resolve_secret({:system, env_var}) do
    System.get_env(env_var) ||
      raise "Environment variable #{env_var} not set for webhook secret"
  end

  defp resolve_secret({module, function, args}) when is_atom(module) and is_atom(function) do
    apply(module, function, args)
  end

  defp decode_payload(body) do
    case Jason.decode(body) do
      {:ok, payload} when is_map(payload) -> {:ok, payload}
      {:ok, _} -> {:error, :invalid_json}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  defp default_error_handler(conn, :missing_body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(400, Jason.encode!(%{error: "Missing request body"}))
    |> halt()
  end

  defp default_error_handler(conn, :missing_signature) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(400, Jason.encode!(%{error: "Missing signature header"}))
    |> halt()
  end

  defp default_error_handler(conn, :invalid_signature) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: "Invalid signature"}))
    |> halt()
  end

  defp default_error_handler(conn, :invalid_json) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(422, Jason.encode!(%{error: "Invalid JSON payload"}))
    |> halt()
  end
end
