defmodule Fivetrex.ConnectorsTest do
  use ExUnit.Case, async: true

  import Fivetrex.TestHelpers

  alias Fivetrex.Connectors
  alias Fivetrex.Models.Connector
  alias Fivetrex.Models.SyncStatus

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, client: client_with_bypass(bypass)}
  end

  describe "list/3" do
    test "returns connectors in a group", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/groups/g1/connectors", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          list_response([
            %{
              "id" => "c1",
              "group_id" => "g1",
              "service" => "postgres",
              "paused" => false,
              "status" => %{"sync_state" => "scheduled"}
            },
            %{
              "id" => "c2",
              "group_id" => "g1",
              "service" => "salesforce",
              "paused" => true,
              "status" => %{"sync_state" => "paused"}
            }
          ])
        )
      end)

      assert {:ok, %{items: connectors, next_cursor: nil}} = Connectors.list(client, "g1")
      assert length(connectors) == 2
      assert [%Connector{id: "c1", service: "postgres"}, %Connector{id: "c2"}] = connectors
    end
  end

  describe "get/2" do
    test "returns a connector", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/connectors/c1", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "id" => "c1",
            "group_id" => "g1",
            "service" => "postgres",
            "paused" => false,
            "status" => %{"sync_state" => "syncing"}
          })
        )
      end)

      assert {:ok, %Connector{id: "c1", service: "postgres"}} = Connectors.get(client, "c1")
    end
  end

  describe "create/2" do
    test "creates a connector", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/connectors", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["group_id"] == "g1"
        assert decoded["service"] == "postgres"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "id" => "new_connector",
            "group_id" => "g1",
            "service" => "postgres"
          })
        )
      end)

      assert {:ok, %Connector{id: "new_connector"}} =
               Connectors.create(client, %{
                 group_id: "g1",
                 service: "postgres",
                 config: %{host: "localhost"}
               })
    end
  end

  describe "update/3" do
    test "updates a connector", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "PATCH", "/connectors/c1", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"paused" => true}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "id" => "c1",
            "paused" => true
          })
        )
      end)

      assert {:ok, %Connector{paused: true}} =
               Connectors.update(client, "c1", %{paused: true})
    end
  end

  describe "delete/2" do
    test "deletes a connector", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "DELETE", "/connectors/c1", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, success_response(%{}))
      end)

      assert :ok = Connectors.delete(client, "c1")
    end
  end

  describe "sync/2" do
    test "triggers a sync and returns normalized response", %{bypass: bypass, client: client} do
      # Real Fivetran API returns {"code": "Success", "message": "..."} for sync
      response = Jason.encode!(%{"code" => "Success", "message" => "Sync triggered"})

      Bypass.expect_once(bypass, "POST", "/connectors/c1/sync", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, response)
      end)

      assert {:ok, %{success: true, message: "Sync triggered"}} =
               Connectors.sync(client, "c1")
    end

    test "extracts sync_state from data response", %{bypass: bypass, client: client} do
      # Some API responses include data with status
      response =
        Jason.encode!(%{
          "code" => "Success",
          "data" => %{
            "status" => %{"sync_state" => "syncing"}
          }
        })

      Bypass.expect_once(bypass, "POST", "/connectors/c1/sync", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, response)
      end)

      assert {:ok, %{success: true, sync_state: "syncing"}} =
               Connectors.sync(client, "c1")
    end

    test "handles response with data but no status", %{bypass: bypass, client: client} do
      response = Jason.encode!(%{"data" => %{"id" => "c1"}})

      Bypass.expect_once(bypass, "POST", "/connectors/c1/sync", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, response)
      end)

      assert {:ok, %{success: true, message: nil, sync_state: nil}} =
               Connectors.sync(client, "c1")
    end
  end

  describe "resync!/3" do
    test "requires confirmation", %{client: client} do
      assert_raise ArgumentError, ~r/confirm: true/, fn ->
        Connectors.resync!(client, "c1", [])
      end
    end

    test "triggers resync with confirmation", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/connectors/c1/resync", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, success_response(%{"syncing" => true}))
      end)

      assert {:ok, _} = Connectors.resync!(client, "c1", confirm: true)
    end
  end

  describe "get_state/2" do
    test "returns connector state", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/connectors/c1/state", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "state" => %{"cursor" => "abc123"}
          })
        )
      end)

      assert {:ok, %{"state" => %{"cursor" => "abc123"}}} = Connectors.get_state(client, "c1")
    end
  end

  describe "pause/2" do
    test "pauses a connector", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "PATCH", "/connectors/c1", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"paused" => true}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "id" => "c1",
            "paused" => true
          })
        )
      end)

      assert {:ok, %Connector{paused: true}} = Connectors.pause(client, "c1")
    end
  end

  describe "resume/2" do
    test "resumes a connector", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "PATCH", "/connectors/c1", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"paused" => false}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "id" => "c1",
            "paused" => false
          })
        )
      end)

      assert {:ok, %Connector{paused: false}} = Connectors.resume(client, "c1")
    end
  end

  # ===========================================================================
  # Schema Configuration Tests
  # ===========================================================================

  alias Fivetrex.Models.Column
  alias Fivetrex.Models.SchemaConfig

  describe "get_schema_config/2" do
    test "returns schema configuration", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/connectors/c1/schemas", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "enable_new_by_default" => true,
            "schema_change_handling" => "ALLOW_ALL",
            "schemas" => %{
              "public" => %{
                "name_in_destination" => "public",
                "enabled" => true,
                "tables" => %{
                  "users" => %{
                    "name_in_destination" => "users",
                    "enabled" => true,
                    "sync_mode" => "SOFT_DELETE"
                  }
                }
              }
            }
          })
        )
      end)

      assert {:ok, %SchemaConfig{} = config} = Connectors.get_schema_config(client, "c1")
      assert config.enable_new_by_default == true
      assert config.schema_change_handling == "ALLOW_ALL"
      assert Map.has_key?(config.schemas, "public")
      assert config.schemas["public"].enabled == true
      assert config.schemas["public"].tables["users"].sync_mode == "SOFT_DELETE"
    end

    test "returns error for non-existent connector", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/connectors/nonexistent/schemas", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, error_response("Connector not found"))
      end)

      assert {:error, %Fivetrex.Error{type: :not_found}} =
               Connectors.get_schema_config(client, "nonexistent")
    end
  end

  describe "get_table_columns/4" do
    test "returns table columns", %{bypass: bypass, client: client} do
      Bypass.expect_once(
        bypass,
        "GET",
        "/connectors/c1/schemas/public/tables/users/columns",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(
            200,
            success_response(%{
              "columns" => %{
                "id" => %{
                  "name_in_destination" => "id",
                  "enabled" => true,
                  "is_primary_key" => true,
                  "hashed" => false
                },
                "email" => %{
                  "name_in_destination" => "email",
                  "enabled" => true,
                  "is_primary_key" => false,
                  "hashed" => true
                }
              }
            })
          )
        end
      )

      assert {:ok, columns} = Connectors.get_table_columns(client, "c1", "public", "users")
      assert Map.has_key?(columns, "id")
      assert Map.has_key?(columns, "email")
      assert %Column{is_primary_key: true} = columns["id"]
      assert %Column{hashed: true} = columns["email"]
    end

    test "parses column type field from API response", %{bypass: bypass, client: client} do
      Bypass.expect_once(
        bypass,
        "GET",
        "/connectors/c1/schemas/public/tables/users/columns",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(
            200,
            success_response(%{
              "columns" => %{
                "id" => %{
                  "name_in_destination" => "id",
                  "enabled" => true,
                  "is_primary_key" => true,
                  "type" => "INTEGER"
                },
                "email" => %{
                  "name_in_destination" => "email",
                  "enabled" => true,
                  "is_primary_key" => false,
                  "type" => "STRING"
                },
                "created_at" => %{
                  "name_in_destination" => "created_at",
                  "enabled" => true,
                  "is_primary_key" => false,
                  "type" => "TIMESTAMP"
                },
                "balance" => %{
                  "name_in_destination" => "balance",
                  "enabled" => true,
                  "is_primary_key" => false,
                  "type" => "FLOAT"
                },
                "active" => %{
                  "name_in_destination" => "active",
                  "enabled" => true,
                  "is_primary_key" => false,
                  "type" => "BOOLEAN"
                }
              }
            })
          )
        end
      )

      assert {:ok, columns} = Connectors.get_table_columns(client, "c1", "public", "users")
      assert %Column{type: "INTEGER"} = columns["id"]
      assert %Column{type: "STRING"} = columns["email"]
      assert %Column{type: "TIMESTAMP"} = columns["created_at"]
      assert %Column{type: "FLOAT"} = columns["balance"]
      assert %Column{type: "BOOLEAN"} = columns["active"]
    end
  end

  describe "update_schema_config/3" do
    test "updates schema configuration", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "PATCH", "/connectors/c1/schemas", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["schemas"]["public"]["tables"]["sensitive"]["enabled"] == false

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "schema_change_handling" => "ALLOW_ALL",
            "schemas" => %{
              "public" => %{
                "enabled" => true,
                "tables" => %{
                  "sensitive" => %{
                    "enabled" => false
                  }
                }
              }
            }
          })
        )
      end)

      assert {:ok, %SchemaConfig{}} =
               Connectors.update_schema_config(client, "c1", %{
                 schemas: %{
                   "public" => %{
                     tables: %{
                       "sensitive" => %{enabled: false}
                     }
                   }
                 }
               })
    end
  end

  describe "reload_schema_config/3" do
    test "reloads schema configuration", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/connectors/c1/schemas/reload", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "schema_change_handling" => "ALLOW_ALL",
            "schemas" => %{}
          })
        )
      end)

      assert {:ok, %SchemaConfig{}} = Connectors.reload_schema_config(client, "c1")
    end

    test "reloads with exclude_mode option", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/connectors/c1/schemas/reload", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"exclude_mode" => "EXCLUDE"}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "schema_change_handling" => "BLOCK_ALL",
            "schemas" => %{}
          })
        )
      end)

      assert {:ok, %SchemaConfig{}} =
               Connectors.reload_schema_config(client, "c1", exclude_mode: "EXCLUDE")
    end
  end

  # ===========================================================================
  # Sync Status and Frequency Tests
  # ===========================================================================

  describe "get_sync_status/2" do
    test "returns SyncStatus struct", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/connectors/c1", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "id" => "c1",
            "status" => %{
              "sync_state" => "syncing",
              "is_historical_sync" => false,
              "update_state" => "on_schedule"
            },
            "succeeded_at" => "2024-01-01T00:00:00Z",
            "failed_at" => nil
          })
        )
      end)

      assert {:ok, %SyncStatus{} = status} = Connectors.get_sync_status(client, "c1")
      assert status.sync_state == "syncing"
      assert status.succeeded_at == ~U[2024-01-01 00:00:00Z]
      assert status.failed_at == nil
      assert status.is_historical_sync == false
      assert status.update_state == "on_schedule"
    end
  end

  describe "set_sync_frequency/4" do
    test "sets sync frequency", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "PATCH", "/connectors/c1", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"sync_frequency" => 60}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "id" => "c1",
            "sync_frequency" => 60
          })
        )
      end)

      assert {:ok, %Connector{sync_frequency: 60}} =
               Connectors.set_sync_frequency(client, "c1", 60)
    end

    test "sets sync frequency with options", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "PATCH", "/connectors/c1", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["sync_frequency"] == 1440
        assert decoded["schedule_type"] == "manual"
        assert decoded["daily_sync_time"] == "14:00"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "id" => "c1",
            "sync_frequency" => 1440
          })
        )
      end)

      assert {:ok, %Connector{}} =
               Connectors.set_sync_frequency(client, "c1", 1440,
                 schedule_type: "manual",
                 daily_sync_time: "14:00"
               )
    end
  end
end

defmodule Fivetrex.Models.ConnectorTest do
  use ExUnit.Case, async: true

  alias Fivetrex.Models.Connector

  describe "sync_state/1" do
    test "returns sync state from status" do
      connector = %Connector{status: %{"sync_state" => "syncing"}}
      assert Connector.sync_state(connector) == "syncing"
    end

    test "returns nil when no status" do
      connector = %Connector{status: nil}
      assert Connector.sync_state(connector) == nil
    end
  end

  describe "syncing?/1" do
    test "returns true when syncing" do
      connector = %Connector{status: %{"sync_state" => "syncing"}}
      assert Connector.syncing?(connector)
    end

    test "returns false when not syncing" do
      connector = %Connector{status: %{"sync_state" => "scheduled"}}
      refute Connector.syncing?(connector)
    end
  end

  describe "paused?/1" do
    test "returns true when paused" do
      connector = %Connector{paused: true}
      assert Connector.paused?(connector)
    end

    test "returns false when not paused" do
      connector = %Connector{paused: false}
      refute Connector.paused?(connector)
    end
  end
end
