defmodule Fivetrex.WebhookSignature do
  @moduledoc """
  HMAC-SHA256 signature verification for Fivetran webhook payloads.

  When you create a webhook with a secret, Fivetran signs each request body
  using HMAC-SHA256 and includes the signature in the `X-Fivetran-Signature-256`
  header. This module provides functions to verify these signatures.

  ## Security

  Signature verification is crucial for ensuring webhook requests actually
  originate from Fivetran and haven't been tampered with. Always verify
  signatures before processing webhook payloads.

  ## Usage

  In your webhook handler (e.g., a Phoenix controller):

      def webhook(conn, _params) do
        signature = get_req_header(conn, "x-fivetran-signature-256") |> List.first()
        body = conn.assigns[:raw_body]  # Requires custom plug to capture raw body
        secret = Application.get_env(:my_app, :fivetran_webhook_secret)

        case Fivetrex.WebhookSignature.verify(body, signature, secret) do
          :ok ->
            # Process the webhook
            json(conn, %{status: "ok"})

          {:error, :invalid_signature} ->
            conn |> put_status(401) |> json(%{error: "Invalid signature"})

          {:error, :missing_signature} ->
            conn |> put_status(400) |> json(%{error: "Missing signature"})
        end
      end

  ## Capturing Raw Body

  To verify signatures, you need access to the raw request body. Phoenix
  typically parses JSON automatically, so you need to capture the raw body
  first. Add a custom plug:

      # In your endpoint.ex, before Plug.Parsers:
      plug :capture_raw_body

      defp capture_raw_body(conn, _opts) do
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        conn
        |> assign(:raw_body, body)
        |> Plug.Conn.put_req_header("x-raw-body", body)
      end

  Or use `Fivetrex.WebhookPlug` which handles this automatically.

  ## Security Notes

    * This module uses constant-time comparison via `Plug.Crypto.secure_compare/2`
      to prevent timing attacks
    * Store webhook secrets securely (environment variables, secrets manager)
    * Never log secrets or raw signatures in production
    * Rotate secrets periodically

  ## See Also

    * `Fivetrex.Webhooks` - API functions for managing webhooks
    * `Fivetrex.WebhookPlug` - Plug that handles signature verification
    * `Fivetrex.Models.WebhookEvent` - Struct for parsing webhook payloads
  """

  @signature_header "x-fivetran-signature-256"

  @doc """
  Verifies that a webhook payload signature is valid.

  Computes the expected HMAC-SHA256 signature for the payload using the
  provided secret and compares it to the signature from the request header.

  ## Parameters

    * `payload` - The raw request body as a string (before JSON parsing)
    * `signature` - The signature from the `X-Fivetran-Signature-256` header
    * `secret` - Your webhook secret configured in Fivetran

  ## Returns

    * `:ok` - Signature is valid
    * `{:error, :invalid_signature}` - Signature does not match
    * `{:error, :missing_signature}` - No signature provided (nil or empty)

  ## Examples

      # Valid signature
      payload = ~s({"event":"sync_end","connector_id":"abc123"})
      secret = "my_webhook_secret"
      signature = Fivetrex.WebhookSignature.compute_signature(payload, secret)

      :ok = Fivetrex.WebhookSignature.verify(payload, signature, secret)

      # Invalid signature
      {:error, :invalid_signature} =
        Fivetrex.WebhookSignature.verify(payload, "wrong_signature", secret)

      # Missing signature
      {:error, :missing_signature} =
        Fivetrex.WebhookSignature.verify(payload, nil, secret)

  """
  @spec verify(String.t(), String.t() | nil, String.t()) ::
          :ok | {:error, :invalid_signature | :missing_signature}
  def verify(_payload, nil, _secret), do: {:error, :missing_signature}
  def verify(_payload, "", _secret), do: {:error, :missing_signature}

  def verify(payload, signature, secret) when is_binary(payload) and is_binary(secret) do
    expected = compute_signature(payload, secret)

    # Normalize both to uppercase for comparison
    normalized_signature = String.upcase(signature)

    if Plug.Crypto.secure_compare(expected, normalized_signature) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  @doc """
  Computes the HMAC-SHA256 signature for a payload.

  Returns the hex-encoded signature in uppercase, matching Fivetran's format.

  ## Parameters

    * `payload` - The raw request body as a string
    * `secret` - Your webhook secret

  ## Returns

  The hex-encoded HMAC-SHA256 signature in uppercase.

  ## Examples

      signature = Fivetrex.WebhookSignature.compute_signature(
        ~s({"event":"sync_end"}),
        "my_secret"
      )
      # Returns something like "A1B2C3D4..."

  """
  @spec compute_signature(String.t(), String.t()) :: String.t()
  def compute_signature(payload, secret) when is_binary(payload) and is_binary(secret) do
    :crypto.mac(:hmac, :sha256, secret, payload)
    |> Base.encode16(case: :upper)
  end

  @doc """
  Returns the expected HTTP header name for Fivetran signatures.

  Fivetran sends the signature in the `X-Fivetran-Signature-256` header.
  Use this function to get the header name for extracting signatures from
  incoming requests.

  ## Returns

  The string `"x-fivetran-signature-256"` (lowercase, as headers are
  case-insensitive in HTTP).

  ## Examples

      header_name = Fivetrex.WebhookSignature.signature_header()
      signature = get_req_header(conn, header_name) |> List.first()

  """
  @spec signature_header() :: String.t()
  def signature_header, do: @signature_header
end
