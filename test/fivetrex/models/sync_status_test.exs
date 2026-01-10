defmodule Fivetrex.Models.SyncStatusTest do
  use ExUnit.Case, async: true

  alias Fivetrex.Models.Connector
  alias Fivetrex.Models.SyncStatus

  describe "syncing?/1" do
    test "returns true when sync_state is syncing" do
      status = %SyncStatus{sync_state: "syncing"}
      assert SyncStatus.syncing?(status)
    end

    test "returns false when sync_state is not syncing" do
      status = %SyncStatus{sync_state: "scheduled"}
      refute SyncStatus.syncing?(status)
    end

    test "returns false when sync_state is nil" do
      status = %SyncStatus{sync_state: nil}
      refute SyncStatus.syncing?(status)
    end
  end

  describe "paused?/1" do
    test "returns true when sync_state is paused" do
      status = %SyncStatus{sync_state: "paused"}
      assert SyncStatus.paused?(status)
    end

    test "returns false when sync_state is not paused" do
      status = %SyncStatus{sync_state: "syncing"}
      refute SyncStatus.paused?(status)
    end

    test "returns false when sync_state is nil" do
      status = %SyncStatus{sync_state: nil}
      refute SyncStatus.paused?(status)
    end
  end

  describe "scheduled?/1" do
    test "returns true when sync_state is scheduled" do
      status = %SyncStatus{sync_state: "scheduled"}
      assert SyncStatus.scheduled?(status)
    end

    test "returns false when sync_state is not scheduled" do
      status = %SyncStatus{sync_state: "syncing"}
      refute SyncStatus.scheduled?(status)
    end

    test "returns false when sync_state is nil" do
      status = %SyncStatus{sync_state: nil}
      refute SyncStatus.scheduled?(status)
    end
  end

  describe "from_connector/1" do
    test "extracts sync status fields from connector" do
      connector = %Connector{
        status: %{
          "sync_state" => "syncing",
          "is_historical_sync" => true,
          "update_state" => "delayed"
        },
        succeeded_at: "2024-01-15T10:30:00Z",
        failed_at: "2024-01-14T08:00:00Z"
      }

      status = SyncStatus.from_connector(connector)

      assert %SyncStatus{} = status
      assert status.sync_state == "syncing"
      assert status.succeeded_at == ~U[2024-01-15 10:30:00Z]
      assert status.failed_at == ~U[2024-01-14 08:00:00Z]
      assert status.is_historical_sync == true
      assert status.update_state == "delayed"
    end

    test "handles connector with nil status" do
      connector = %Connector{
        status: nil,
        succeeded_at: "2024-01-15T10:30:00Z",
        failed_at: nil
      }

      status = SyncStatus.from_connector(connector)

      assert %SyncStatus{} = status
      assert status.sync_state == nil
      assert status.succeeded_at == ~U[2024-01-15 10:30:00Z]
      assert status.failed_at == nil
      assert status.is_historical_sync == nil
      assert status.update_state == nil
    end

    test "handles connector with partial status" do
      connector = %Connector{
        status: %{"sync_state" => "scheduled"},
        succeeded_at: nil,
        failed_at: nil
      }

      status = SyncStatus.from_connector(connector)

      assert %SyncStatus{} = status
      assert status.sync_state == "scheduled"
      assert status.succeeded_at == nil
      assert status.failed_at == nil
      assert status.is_historical_sync == nil
      assert status.update_state == nil
    end

    test "parses succeeded_at and failed_at as DateTime" do
      connector = %Connector{
        status: %{"sync_state" => "scheduled"},
        succeeded_at: "2024-06-15T14:30:00Z",
        failed_at: "2024-06-14T10:00:00Z"
      }

      status = SyncStatus.from_connector(connector)

      assert %DateTime{} = status.succeeded_at
      assert %DateTime{} = status.failed_at
      assert status.succeeded_at == ~U[2024-06-15 14:30:00Z]
      assert status.failed_at == ~U[2024-06-14 10:00:00Z]
    end

    test "handles invalid datetime strings" do
      connector = %Connector{
        status: %{"sync_state" => "scheduled"},
        succeeded_at: "not-a-date",
        failed_at: "also-not-a-date"
      }

      status = SyncStatus.from_connector(connector)

      assert status.succeeded_at == nil
      assert status.failed_at == nil
    end

    test "handles DateTime values that are already parsed" do
      connector = %Connector{
        status: %{"sync_state" => "scheduled"},
        succeeded_at: ~U[2024-06-15 14:30:00Z],
        failed_at: nil
      }

      status = SyncStatus.from_connector(connector)

      assert status.succeeded_at == ~U[2024-06-15 14:30:00Z]
      assert status.failed_at == nil
    end
  end
end
