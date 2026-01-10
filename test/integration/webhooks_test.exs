defmodule Fivetrex.Integration.WebhooksTest do
  @moduledoc """
  Integration tests for Webhook CRUD operations.

  These tests create real webhooks in your Fivetran account. Since webhooks
  require a valid URL endpoint, we use a non-routable URL that won't receive
  actual webhook calls and keep webhooks inactive.

  Run with: mix test --include integration test/integration/webhooks_test.exs
  """

  use ExUnit.Case

  @moduletag :integration

  import Fivetrex.TestHelpers

  alias Fivetrex.Models.Webhook
  alias Fivetrex.Webhooks

  # Using a non-routable URL for testing (won't actually receive webhooks)
  @test_url "https://example.invalid/webhook/fivetrex-test"

  defp unique_suffix, do: System.unique_integer([:positive])

  describe "webhook CRUD lifecycle" do
    setup do
      client = integration_client()

      # Create a test group for group-level webhook tests
      group_name = "fivetrex_webhook_test_#{unique_suffix()}"
      {:ok, group} = Fivetrex.Groups.create(client, %{name: group_name})

      on_exit(fn ->
        # Clean up the test group
        Fivetrex.Groups.delete(client, group.id)
      end)

      {:ok, client: client, group_id: group.id}
    end

    test "creates and deletes an account webhook", %{client: client} do
      # Create
      {:ok, webhook} =
        Webhooks.create_account(client, %{
          url: @test_url,
          events: ["sync_end"],
          # Keep inactive to avoid delivery attempts
          active: false
        })

      assert %Webhook{} = webhook
      assert webhook.type == "account"
      assert webhook.url == @test_url
      assert webhook.active == false
      webhook_id = webhook.id

      # Get
      {:ok, fetched} = Webhooks.get(client, webhook_id)
      assert fetched.id == webhook_id
      assert fetched.url == @test_url

      # Delete
      assert :ok = Webhooks.delete(client, webhook_id)

      # Verify deletion
      assert {:error, %Fivetrex.Error{type: :not_found}} =
               Webhooks.get(client, webhook_id)
    end

    test "creates a group webhook", %{client: client, group_id: group_id} do
      {:ok, webhook} =
        Webhooks.create_group(client, group_id, %{
          url: @test_url,
          events: ["sync_start", "sync_end"],
          active: false
        })

      assert %Webhook{} = webhook
      assert webhook.type == "group"
      assert webhook.group_id == group_id
      assert webhook.events == ["sync_start", "sync_end"]

      # Cleanup
      Webhooks.delete(client, webhook.id)
    end

    test "updates a webhook", %{client: client} do
      {:ok, webhook} =
        Webhooks.create_account(client, %{
          url: @test_url,
          events: ["sync_end"],
          active: false
        })

      # Update events
      {:ok, updated} =
        Webhooks.update(client, webhook.id, %{
          events: ["sync_start", "sync_end"]
        })

      assert "sync_start" in updated.events
      assert "sync_end" in updated.events

      # Cleanup
      Webhooks.delete(client, webhook.id)
    end

    test "lists webhooks includes created webhook", %{client: client} do
      {:ok, webhook} =
        Webhooks.create_account(client, %{
          url: @test_url,
          events: ["sync_end"],
          active: false
        })

      {:ok, %{items: webhooks}} = Webhooks.list(client)
      assert Enum.any?(webhooks, &(&1.id == webhook.id))

      # Cleanup
      Webhooks.delete(client, webhook.id)
    end

    test "streams webhooks", %{client: client} do
      {:ok, webhook} =
        Webhooks.create_account(client, %{
          url: @test_url,
          events: ["sync_end"],
          active: false
        })

      # Stream and find our webhook
      found =
        client
        |> Webhooks.stream()
        |> Enum.find(&(&1.id == webhook.id))

      assert found != nil
      assert found.id == webhook.id

      # Cleanup
      Webhooks.delete(client, webhook.id)
    end
  end

  describe "error handling" do
    setup do
      {:ok, client: integration_client()}
    end

    test "returns not_found for non-existent webhook", %{client: client} do
      assert {:error, %Fivetrex.Error{type: :not_found}} =
               Webhooks.get(client, "nonexistent_webhook_id_12345")
    end

    test "returns not_found when deleting non-existent webhook", %{client: client} do
      assert {:error, %Fivetrex.Error{type: :not_found}} =
               Webhooks.delete(client, "nonexistent_webhook_id_12345")
    end
  end
end
