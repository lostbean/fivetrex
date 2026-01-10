defmodule Fivetrex.WebhookPlugTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Fivetrex.Models.WebhookEvent
  alias Fivetrex.WebhookPlug
  alias Fivetrex.WebhookSignature

  @secret "test_webhook_secret"
  @valid_payload Jason.encode!(%{
                   "event" => "sync_end",
                   "connector_id" => "conn123",
                   "connector_type" => "postgres",
                   "group_id" => "g1",
                   "data" => %{"status" => "SUCCESSFUL"}
                 })

  defp sign_payload(payload, secret \\ @secret) do
    WebhookSignature.compute_signature(payload, secret)
  end

  defp build_conn(payload, signature) do
    conn(:post, "/webhook", payload)
    |> put_req_header("content-type", "application/json")
    |> put_req_header(WebhookSignature.signature_header(), signature)
    |> put_private(:fivetrex_raw_body, payload)
  end

  describe "init/1" do
    test "requires secret option" do
      assert_raise KeyError, fn ->
        WebhookPlug.init([])
      end
    end

    test "accepts secret as string" do
      opts = WebhookPlug.init(secret: "my_secret")
      assert opts.secret == "my_secret"
    end

    test "accepts secret as MFA tuple" do
      opts = WebhookPlug.init(secret: {String, :upcase, ["test"]})
      assert opts.secret == {String, :upcase, ["test"]}
    end

    test "accepts secret as system env tuple" do
      opts = WebhookPlug.init(secret: {:system, "MY_SECRET_VAR"})
      assert opts.secret == {:system, "MY_SECRET_VAR"}
    end

    test "uses default event_key" do
      opts = WebhookPlug.init(secret: "test")
      assert opts.event_key == :fivetran_event
    end

    test "accepts custom event_key" do
      opts = WebhookPlug.init(secret: "test", event_key: :webhook_event)
      assert opts.event_key == :webhook_event
    end
  end

  describe "call/2 with valid signature" do
    setup do
      signature = sign_payload(@valid_payload)
      conn = build_conn(@valid_payload, signature)
      opts = WebhookPlug.init(secret: @secret)
      {:ok, conn: conn, opts: opts}
    end

    test "assigns fivetran_event", %{conn: conn, opts: opts} do
      conn = WebhookPlug.call(conn, opts)

      assert %WebhookEvent{} = conn.assigns.fivetran_event
      assert conn.assigns.fivetran_event.event == "sync_end"
      assert conn.assigns.fivetran_event.connector_id == "conn123"
    end

    test "assigns raw_body", %{conn: conn, opts: opts} do
      conn = WebhookPlug.call(conn, opts)

      assert conn.assigns.raw_body == @valid_payload
    end

    test "does not halt connection", %{conn: conn, opts: opts} do
      conn = WebhookPlug.call(conn, opts)

      refute conn.halted
    end

    test "uses custom event_key", %{conn: conn} do
      opts = WebhookPlug.init(secret: @secret, event_key: :my_event)
      conn = WebhookPlug.call(conn, opts)

      assert %WebhookEvent{} = conn.assigns.my_event
      refute Map.has_key?(conn.assigns, :fivetran_event)
    end
  end

  describe "call/2 with invalid signature" do
    test "returns 401 for invalid signature" do
      conn = build_conn(@valid_payload, "invalid_signature")
      opts = WebhookPlug.init(secret: @secret)

      conn = WebhookPlug.call(conn, opts)

      assert conn.halted
      assert conn.status == 401
      assert Jason.decode!(conn.resp_body) == %{"error" => "Invalid signature"}
    end

    test "returns 401 when secret is wrong" do
      signature = sign_payload(@valid_payload, "wrong_secret")
      conn = build_conn(@valid_payload, signature)
      opts = WebhookPlug.init(secret: @secret)

      conn = WebhookPlug.call(conn, opts)

      assert conn.halted
      assert conn.status == 401
    end
  end

  describe "call/2 with missing signature" do
    test "returns 400 for missing signature header" do
      conn =
        conn(:post, "/webhook", @valid_payload)
        |> put_req_header("content-type", "application/json")
        |> put_private(:fivetrex_raw_body, @valid_payload)

      opts = WebhookPlug.init(secret: @secret)

      conn = WebhookPlug.call(conn, opts)

      assert conn.halted
      assert conn.status == 400
      assert Jason.decode!(conn.resp_body) == %{"error" => "Missing signature header"}
    end

    test "returns 400 for empty signature header" do
      conn = build_conn(@valid_payload, "")
      opts = WebhookPlug.init(secret: @secret)

      conn = WebhookPlug.call(conn, opts)

      assert conn.halted
      assert conn.status == 400
    end
  end

  describe "call/2 with missing body" do
    test "returns 400 when raw body not cached" do
      signature = sign_payload(@valid_payload)

      conn =
        conn(:post, "/webhook", @valid_payload)
        |> put_req_header("content-type", "application/json")
        |> put_req_header(WebhookSignature.signature_header(), signature)

      # Note: NOT putting :fivetrex_raw_body in private

      opts = WebhookPlug.init(secret: @secret)

      conn = WebhookPlug.call(conn, opts)

      assert conn.halted
      assert conn.status == 400
      assert Jason.decode!(conn.resp_body) == %{"error" => "Missing request body"}
    end
  end

  describe "call/2 with invalid JSON" do
    test "returns 422 for invalid JSON" do
      invalid_json = "not valid json {"
      signature = sign_payload(invalid_json)
      conn = build_conn(invalid_json, signature)
      opts = WebhookPlug.init(secret: @secret)

      conn = WebhookPlug.call(conn, opts)

      assert conn.halted
      assert conn.status == 422
      assert Jason.decode!(conn.resp_body) == %{"error" => "Invalid JSON payload"}
    end

    test "returns 422 for non-object JSON" do
      array_json = "[1, 2, 3]"
      signature = sign_payload(array_json)
      conn = build_conn(array_json, signature)
      opts = WebhookPlug.init(secret: @secret)

      conn = WebhookPlug.call(conn, opts)

      assert conn.halted
      assert conn.status == 422
    end
  end

  describe "call/2 with MFA secret" do
    test "resolves secret from MFA tuple" do
      # Use a simple function that returns the secret
      opts = WebhookPlug.init(secret: {__MODULE__, :get_test_secret, []})
      signature = sign_payload(@valid_payload)
      conn = build_conn(@valid_payload, signature)

      conn = WebhookPlug.call(conn, opts)

      refute conn.halted
      assert conn.assigns.fivetran_event.event == "sync_end"
    end
  end

  describe "call/2 with system env secret" do
    test "resolves secret from environment variable" do
      System.put_env("TEST_WEBHOOK_SECRET", @secret)

      on_exit(fn ->
        System.delete_env("TEST_WEBHOOK_SECRET")
      end)

      opts = WebhookPlug.init(secret: {:system, "TEST_WEBHOOK_SECRET"})
      signature = sign_payload(@valid_payload)
      conn = build_conn(@valid_payload, signature)

      conn = WebhookPlug.call(conn, opts)

      refute conn.halted
      assert conn.assigns.fivetran_event.event == "sync_end"
    end

    test "raises when environment variable not set" do
      opts = WebhookPlug.init(secret: {:system, "NONEXISTENT_VAR_12345"})
      signature = sign_payload(@valid_payload)
      conn = build_conn(@valid_payload, signature)

      assert_raise RuntimeError, ~r/Environment variable/, fn ->
        WebhookPlug.call(conn, opts)
      end
    end
  end

  describe "call/2 with custom error handler" do
    test "uses custom error handler" do
      custom_handler = fn conn, error_type ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(403, "Custom error: #{error_type}")
        |> Plug.Conn.halt()
      end

      opts = WebhookPlug.init(secret: @secret, on_error: custom_handler)
      conn = build_conn(@valid_payload, "invalid")

      conn = WebhookPlug.call(conn, opts)

      assert conn.halted
      assert conn.status == 403
      assert conn.resp_body == "Custom error: invalid_signature"
    end
  end

  describe "cache_raw_body/2" do
    test "caches body in private" do
      # Create a minimal test for the body reader
      # In practice, this is called by Plug.Parsers
      conn = conn(:post, "/", "test body")

      # Simulate what Plug.Parsers would do
      {:ok, body, conn} = WebhookPlug.cache_raw_body(conn, [])

      assert body == "test body"
      assert conn.private[:fivetrex_raw_body] == "test body"
    end
  end

  # Helper function for MFA secret test
  def get_test_secret, do: @secret
end
