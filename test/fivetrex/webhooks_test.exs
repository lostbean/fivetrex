defmodule Fivetrex.WebhooksTest do
  use ExUnit.Case, async: true

  import Fivetrex.TestHelpers

  alias Fivetrex.Models.Webhook
  alias Fivetrex.Webhooks

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, client: client_with_bypass(bypass)}
  end

  describe "list/2" do
    test "returns webhooks", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/webhooks", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          list_response([
            %{
              "id" => "w1",
              "type" => "account",
              "url" => "https://example.com/webhook",
              "events" => ["sync_end"],
              "active" => true
            },
            %{
              "id" => "w2",
              "type" => "group",
              "group_id" => "g1",
              "url" => "https://example.com/webhook2",
              "events" => ["sync_start"],
              "active" => false
            }
          ])
        )
      end)

      assert {:ok, %{items: webhooks, next_cursor: nil}} = Webhooks.list(client)
      assert length(webhooks) == 2
      assert [%Webhook{id: "w1", type: "account"}, %Webhook{id: "w2", type: "group"}] = webhooks
    end

    test "handles pagination", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/webhooks", fn conn ->
        assert conn.query_params["cursor"] == "abc123"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          list_response([
            %{"id" => "w3", "type" => "account"}
          ])
        )
      end)

      assert {:ok, %{items: [%Webhook{id: "w3"}], next_cursor: nil}} =
               Webhooks.list(client, cursor: "abc123")
    end

    test "returns next_cursor when present", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/webhooks", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          list_response(
            [%{"id" => "w1", "type" => "account"}],
            "next_page_cursor"
          )
        )
      end)

      assert {:ok, %{items: _, next_cursor: "next_page_cursor"}} = Webhooks.list(client)
    end
  end

  describe "stream/2" do
    test "streams through multiple pages", %{bypass: bypass, client: client} do
      call_count = :counters.new(1, [:atomics])

      Bypass.expect(bypass, "GET", "/webhooks", fn conn ->
        :counters.add(call_count, 1, 1)
        count = :counters.get(call_count, 1)

        response =
          case {count, conn.query_params["cursor"]} do
            {1, nil} ->
              list_response([%{"id" => "w1", "type" => "account"}], "cursor1")

            {2, "cursor1"} ->
              list_response([%{"id" => "w2", "type" => "group"}], "cursor2")

            {3, "cursor2"} ->
              list_response([%{"id" => "w3", "type" => "account"}])
          end

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, response)
      end)

      webhooks =
        client
        |> Webhooks.stream()
        |> Enum.to_list()

      assert length(webhooks) == 3
      assert Enum.map(webhooks, & &1.id) == ["w1", "w2", "w3"]
    end
  end

  describe "get/2" do
    test "returns a webhook", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/webhooks/w1", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "id" => "w1",
            "type" => "account",
            "url" => "https://example.com/webhook",
            "events" => ["sync_end"],
            "active" => true
          })
        )
      end)

      assert {:ok, %Webhook{id: "w1", type: "account", active: true}} =
               Webhooks.get(client, "w1")
    end

    test "returns error for non-existent webhook", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/webhooks/nonexistent", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, error_response("Webhook not found"))
      end)

      assert {:error, %Fivetrex.Error{type: :not_found}} =
               Webhooks.get(client, "nonexistent")
    end
  end

  describe "create_account/2" do
    test "creates an account webhook", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/webhooks/account", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["url"] == "https://example.com/webhook"
        assert decoded["events"] == ["sync_end"]
        assert decoded["active"] == true

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "id" => "new_webhook",
            "type" => "account",
            "url" => "https://example.com/webhook",
            "events" => ["sync_end"],
            "active" => true
          })
        )
      end)

      assert {:ok, %Webhook{id: "new_webhook", type: "account"}} =
               Webhooks.create_account(client, %{
                 url: "https://example.com/webhook",
                 events: ["sync_end"],
                 active: true
               })
    end
  end

  describe "create_group/3" do
    test "creates a group webhook", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/webhooks/group/g1", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["url"] == "https://example.com/webhook"
        assert decoded["events"] == ["sync_start", "sync_end"]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "id" => "new_webhook",
            "type" => "group",
            "group_id" => "g1",
            "url" => "https://example.com/webhook",
            "events" => ["sync_start", "sync_end"],
            "active" => true
          })
        )
      end)

      assert {:ok, %Webhook{type: "group", group_id: "g1"}} =
               Webhooks.create_group(client, "g1", %{
                 url: "https://example.com/webhook",
                 events: ["sync_start", "sync_end"]
               })
    end
  end

  describe "update/3" do
    test "updates a webhook", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "PATCH", "/webhooks/w1", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"active" => false}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "id" => "w1",
            "type" => "account",
            "active" => false
          })
        )
      end)

      assert {:ok, %Webhook{id: "w1", active: false}} =
               Webhooks.update(client, "w1", %{active: false})
    end

    test "updates events list", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "PATCH", "/webhooks/w1", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"events" => ["sync_start", "sync_end"]}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "id" => "w1",
            "events" => ["sync_start", "sync_end"]
          })
        )
      end)

      assert {:ok, %Webhook{events: ["sync_start", "sync_end"]}} =
               Webhooks.update(client, "w1", %{events: ["sync_start", "sync_end"]})
    end
  end

  describe "delete/2" do
    test "deletes a webhook", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "DELETE", "/webhooks/w1", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, success_response(%{}))
      end)

      assert :ok = Webhooks.delete(client, "w1")
    end

    test "returns error for non-existent webhook", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "DELETE", "/webhooks/nonexistent", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, error_response("Webhook not found"))
      end)

      assert {:error, %Fivetrex.Error{type: :not_found}} =
               Webhooks.delete(client, "nonexistent")
    end
  end

  describe "test/3" do
    test "sends a test event", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/webhooks/w1/test", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{"sent" => true})
        )
      end)

      assert {:ok, %{"sent" => true}} = Webhooks.test(client, "w1")
    end

    test "sends a test event with specific event type", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/webhooks/w1/test", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"event" => "sync_end"}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{"sent" => true, "event" => "sync_end"})
        )
      end)

      assert {:ok, %{"sent" => true}} = Webhooks.test(client, "w1", event: "sync_end")
    end
  end
end

defmodule Fivetrex.Models.WebhookTest do
  use ExUnit.Case, async: true

  alias Fivetrex.Models.Webhook

  describe "from_map/1" do
    test "converts map to struct" do
      map = %{
        "id" => "w1",
        "type" => "account",
        "url" => "https://example.com",
        "events" => ["sync_end"],
        "active" => true,
        "secret" => "secret123",
        "created_at" => "2024-01-01T00:00:00Z",
        "created_by" => "user123"
      }

      webhook = Webhook.from_map(map)

      assert webhook.id == "w1"
      assert webhook.type == "account"
      assert webhook.url == "https://example.com"
      assert webhook.events == ["sync_end"]
      assert webhook.active == true
      assert webhook.secret == "secret123"
      assert webhook.created_at == ~U[2024-01-01 00:00:00Z]
      assert webhook.created_by == "user123"
    end

    test "parses created_at as DateTime" do
      map = %{"id" => "w1", "created_at" => "2024-06-15T14:30:00Z"}
      webhook = Webhook.from_map(map)

      assert %DateTime{} = webhook.created_at
      assert webhook.created_at == ~U[2024-06-15 14:30:00Z]
    end

    test "handles nil created_at" do
      map = %{"id" => "w1", "created_at" => nil}
      webhook = Webhook.from_map(map)

      assert webhook.created_at == nil
    end

    test "handles invalid created_at string" do
      map = %{"id" => "w1", "created_at" => "not-a-date"}
      webhook = Webhook.from_map(map)

      assert webhook.created_at == nil
    end

    test "handles missing fields" do
      map = %{"id" => "w1", "type" => "account"}
      webhook = Webhook.from_map(map)

      assert webhook.id == "w1"
      assert webhook.url == nil
      assert webhook.events == nil
    end
  end

  describe "account_level?/1" do
    test "returns true for account webhooks" do
      webhook = %Webhook{type: "account"}
      assert Webhook.account_level?(webhook)
    end

    test "returns false for group webhooks" do
      webhook = %Webhook{type: "group"}
      refute Webhook.account_level?(webhook)
    end
  end

  describe "group_level?/1" do
    test "returns true for group webhooks" do
      webhook = %Webhook{type: "group", group_id: "g1"}
      assert Webhook.group_level?(webhook)
    end

    test "returns false for account webhooks" do
      webhook = %Webhook{type: "account"}
      refute Webhook.group_level?(webhook)
    end
  end
end

defmodule Fivetrex.Models.WebhookEventTest do
  use ExUnit.Case, async: true

  alias Fivetrex.Models.WebhookEvent

  describe "from_map/1" do
    test "converts map to struct" do
      map = %{
        "event" => "sync_end",
        "created" => "2024-01-01T00:00:00Z",
        "connector_id" => "conn123",
        "connector_type" => "postgres",
        "group_id" => "g1",
        "data" => %{"status" => "SUCCESSFUL"}
      }

      event = WebhookEvent.from_map(map)

      assert event.event == "sync_end"
      assert event.created == ~U[2024-01-01 00:00:00Z]
      assert event.connector_id == "conn123"
      assert event.connector_type == "postgres"
      assert event.data == %{"status" => "SUCCESSFUL"}
    end

    test "parses created as DateTime" do
      map = %{"event" => "sync_start", "created" => "2024-06-15T14:30:00Z"}
      event = WebhookEvent.from_map(map)

      assert %DateTime{} = event.created
      assert event.created == ~U[2024-06-15 14:30:00Z]
    end

    test "handles nil created" do
      map = %{"event" => "sync_start", "created" => nil}
      event = WebhookEvent.from_map(map)

      assert event.created == nil
    end

    test "handles invalid created string" do
      map = %{"event" => "sync_start", "created" => "not-a-date"}
      event = WebhookEvent.from_map(map)

      assert event.created == nil
    end
  end

  describe "sync_start?/1" do
    test "returns true for sync_start events" do
      event = %WebhookEvent{event: "sync_start"}
      assert WebhookEvent.sync_start?(event)
    end

    test "returns false for other events" do
      event = %WebhookEvent{event: "sync_end"}
      refute WebhookEvent.sync_start?(event)
    end
  end

  describe "sync_end?/1" do
    test "returns true for sync_end events" do
      event = %WebhookEvent{event: "sync_end"}
      assert WebhookEvent.sync_end?(event)
    end

    test "returns false for other events" do
      event = %WebhookEvent{event: "sync_start"}
      refute WebhookEvent.sync_end?(event)
    end
  end
end
