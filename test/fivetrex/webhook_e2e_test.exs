defmodule Fivetrex.WebhookE2ETest do
  @moduledoc """
  End-to-end tests for the complete webhook handling flow.

  These tests simulate receiving a webhook from Fivetran and processing it
  through all the Fivetrex webhook components.
  """

  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Fivetrex.Models.WebhookEvent
  alias Fivetrex.WebhookPlug
  alias Fivetrex.WebhookSignature

  @secret "e2e_test_secret"

  describe "complete webhook handling flow" do
    test "sync_end event is received, verified, parsed, and identified" do
      # Step 1: Create a realistic Fivetran sync_end payload
      payload =
        Jason.encode!(%{
          "event" => "sync_end",
          "created" => "2024-01-15T10:30:00Z",
          "connector_id" => "connector_abc123",
          "connector_type" => "postgres",
          "group_id" => "group_xyz",
          "data" => %{
            "status" => "SUCCESSFUL",
            "sync_id" => "sync_12345"
          }
        })

      # Step 2: Sign the payload (simulating what Fivetran does)
      signature = WebhookSignature.compute_signature(payload, @secret)

      # Step 3: Build the HTTP request
      conn = build_webhook_request(payload, signature)

      # Step 4: Process through WebhookPlug
      opts = WebhookPlug.init(secret: @secret)
      conn = WebhookPlug.call(conn, opts)

      # Step 5: Verify the connection was not halted (valid signature)
      refute conn.halted

      # Step 6: Extract the parsed event from assigns
      event = conn.assigns.fivetran_event
      assert %WebhookEvent{} = event

      # Step 7: Verify event data
      assert event.event == "sync_end"
      assert event.connector_id == "connector_abc123"
      assert event.connector_type == "postgres"
      assert event.group_id == "group_xyz"
      assert event.data["status"] == "SUCCESSFUL"

      # Step 8: Use helper functions
      assert WebhookEvent.sync_end?(event)
      refute WebhookEvent.sync_start?(event)
    end

    test "sync_start event flow" do
      payload =
        Jason.encode!(%{
          "event" => "sync_start",
          "created" => "2024-01-15T10:00:00Z",
          "connector_id" => "connector_abc123",
          "connector_type" => "salesforce",
          "group_id" => "group_xyz",
          "data" => %{}
        })

      signature = WebhookSignature.compute_signature(payload, @secret)
      conn = build_webhook_request(payload, signature) |> process_webhook()

      event = conn.assigns.fivetran_event

      assert WebhookEvent.sync_start?(event)
      refute WebhookEvent.sync_end?(event)
      assert event.connector_type == "salesforce"
    end

    test "failed sync event includes failure reason" do
      payload =
        Jason.encode!(%{
          "event" => "sync_end",
          "created" => "2024-01-15T10:30:00Z",
          "connector_id" => "connector_abc123",
          "connector_type" => "mysql",
          "group_id" => "group_xyz",
          "data" => %{
            "status" => "FAILURE_WITH_TASK",
            "reason" => "Connection timeout"
          }
        })

      signature = WebhookSignature.compute_signature(payload, @secret)
      conn = build_webhook_request(payload, signature) |> process_webhook()

      event = conn.assigns.fivetran_event

      assert WebhookEvent.sync_end?(event)
      assert event.data["status"] == "FAILURE_WITH_TASK"
      assert event.data["reason"] == "Connection timeout"
    end

    test "invalid signature is rejected at the plug level" do
      payload = Jason.encode!(%{"event" => "sync_end", "connector_id" => "test"})

      # Sign with wrong secret
      wrong_signature = WebhookSignature.compute_signature(payload, "wrong_secret")
      conn = build_webhook_request(payload, wrong_signature) |> process_webhook()

      # Should be halted with 401
      assert conn.halted
      assert conn.status == 401
      refute Map.has_key?(conn.assigns, :fivetran_event)
    end

    test "tampered payload is rejected" do
      original_payload = Jason.encode!(%{"event" => "sync_end", "connector_id" => "test"})
      signature = WebhookSignature.compute_signature(original_payload, @secret)

      # Tamper with the payload after signing
      tampered_payload = Jason.encode!(%{"event" => "sync_end", "connector_id" => "hacked"})

      conn = build_webhook_request(tampered_payload, signature) |> process_webhook()

      assert conn.halted
      assert conn.status == 401
    end
  end

  # Helper functions

  defp build_webhook_request(payload, signature) do
    conn(:post, "/webhook", payload)
    |> put_req_header("content-type", "application/json")
    |> put_req_header(WebhookSignature.signature_header(), signature)
    |> put_private(:fivetrex_raw_body, payload)
  end

  defp process_webhook(conn) do
    opts = WebhookPlug.init(secret: @secret)
    WebhookPlug.call(conn, opts)
  end
end
