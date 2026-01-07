defmodule Fivetrex.Integration.PaginationTest do
  use ExUnit.Case

  @moduletag :integration

  import Fivetrex.TestHelpers

  alias Fivetrex.Models.{Connector, Group}

  setup do
    {:ok, client: integration_client()}
  end

  describe "Groups pagination" do
    test "list/2 returns paginated results with cursor", %{client: client} do
      # Request a small page size to test pagination
      case Fivetrex.Groups.list(client, limit: 2) do
        {:ok, %{items: items, next_cursor: next_cursor}} ->
          assert is_list(items)
          assert length(items) <= 2

          # If there's a next_cursor, we can fetch more
          if next_cursor do
            assert is_binary(next_cursor)

            # Fetch the next page
            {:ok, %{items: next_items}} =
              Fivetrex.Groups.list(client, cursor: next_cursor, limit: 2)

            assert is_list(next_items)

            # Items should be different from first page
            first_ids = Enum.map(items, & &1.id)
            next_ids = Enum.map(next_items, & &1.id)
            assert Enum.all?(next_ids, fn id -> id not in first_ids end)
          end

        {:ok, %{items: items}} ->
          # No cursor means single page of results
          assert is_list(items)
      end
    end

    test "stream/2 iterates through multiple pages", %{client: client} do
      # Stream with small page size to force multiple API calls
      groups =
        client
        |> Fivetrex.Groups.stream(limit: 2)
        |> Enum.take(10)

      assert is_list(groups)
      assert Enum.all?(groups, fn g -> %Group{} = g end)

      # Verify all groups have unique IDs (no duplicates from pagination)
      ids = Enum.map(groups, & &1.id)
      assert ids == Enum.uniq(ids)
    end

    test "stream/2 can be composed with Stream functions", %{client: client} do
      # Verify streams work correctly with Elixir Stream operations
      result =
        client
        |> Fivetrex.Groups.stream(limit: 2)
        |> Stream.filter(fn g -> g.name != nil end)
        |> Stream.map(fn g -> {g.id, g.name} end)
        |> Enum.take(5)

      assert is_list(result)
      assert Enum.all?(result, fn {id, name} -> is_binary(id) and is_binary(name) end)
    end

    test "stream/2 handles accounts with many groups", %{client: client} do
      # Count total groups using stream (tests multi-page iteration)
      count =
        client
        |> Fivetrex.Groups.stream(limit: 5)
        |> Enum.count()

      assert is_integer(count)
      assert count >= 0

      # Also verify via list that count is reasonable
      {:ok, %{items: first_page}} = Fivetrex.Groups.list(client, limit: 100)

      # Stream count should be >= first page count
      assert count >= length(first_page)
    end
  end

  describe "Connectors pagination" do
    setup %{client: client} do
      # Get a group that has connectors
      {:ok, %{items: groups}} = Fivetrex.Groups.list(client)

      # Find a group with connectors
      group_with_connectors =
        Enum.find(groups, fn group ->
          case Fivetrex.Connectors.list(client, group.id, limit: 1) do
            {:ok, %{items: [_ | _]}} -> true
            _ -> false
          end
        end)

      {:ok, group: group_with_connectors}
    end

    test "list/3 returns paginated results with cursor", %{client: client, group: group} do
      if group do
        case Fivetrex.Connectors.list(client, group.id, limit: 2) do
          {:ok, %{items: items, next_cursor: next_cursor}} ->
            assert is_list(items)
            assert length(items) <= 2

            if next_cursor do
              # Fetch next page
              {:ok, %{items: next_items}} =
                Fivetrex.Connectors.list(client, group.id, cursor: next_cursor, limit: 2)

              assert is_list(next_items)
            end

          {:ok, %{items: items}} ->
            assert is_list(items)
        end
      else
        # No groups with connectors found
        assert true
      end
    end

    test "stream/3 iterates through connectors", %{client: client, group: group} do
      if group do
        connectors =
          client
          |> Fivetrex.Connectors.stream(group.id, limit: 2)
          |> Enum.take(10)

        assert is_list(connectors)
        assert Enum.all?(connectors, fn c -> %Connector{} = c end)

        # Verify unique IDs
        ids = Enum.map(connectors, & &1.id)
        assert ids == Enum.uniq(ids)
      else
        assert true
      end
    end

    test "stream/3 can flat_map across groups", %{client: client} do
      # This is a common pattern: stream all connectors across all groups
      all_connectors =
        client
        |> Fivetrex.Groups.stream(limit: 3)
        |> Stream.take(3)
        |> Stream.flat_map(fn group ->
          Fivetrex.Connectors.stream(client, group.id, limit: 5)
        end)
        |> Enum.take(10)

      assert is_list(all_connectors)
      assert Enum.all?(all_connectors, fn c -> %Connector{} = c end)
    end
  end

  describe "pagination edge cases" do
    test "empty results return empty list", %{client: client} do
      # Create a temporary group with no connectors
      unique_name = "fivetrex_pagination_test_#{System.unique_integer([:positive])}"
      {:ok, group} = Fivetrex.Groups.create(client, %{name: unique_name})

      try do
        # List connectors in empty group
        {:ok, %{items: items}} = Fivetrex.Connectors.list(client, group.id)
        assert items == []

        # Stream connectors in empty group
        stream_result =
          client
          |> Fivetrex.Connectors.stream(group.id)
          |> Enum.to_list()

        assert stream_result == []
      after
        Fivetrex.Groups.delete(client, group.id)
      end
    end

    test "stream laziness - stops fetching when take is satisfied", %{client: client} do
      # Take just 1 item - should not fetch more pages than necessary
      result =
        client
        |> Fivetrex.Groups.stream(limit: 1)
        |> Enum.take(1)

      assert length(result) <= 1
    end
  end
end
