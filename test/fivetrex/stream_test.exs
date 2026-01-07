defmodule Fivetrex.StreamTest do
  use ExUnit.Case, async: true

  alias Fivetrex.Error
  alias Fivetrex.Stream

  describe "paginate/1" do
    test "yields items from a single page when next_cursor is nil" do
      fetch_fn = fn nil ->
        {:ok, %{items: [1, 2, 3], next_cursor: nil}}
      end

      result = Stream.paginate(fetch_fn) |> Enum.to_list()

      assert result == [1, 2, 3]
    end

    test "yields items from multiple pages following cursor" do
      call_count = :counters.new(1, [:atomics])

      fetch_fn = fn cursor ->
        :counters.add(call_count, 1, 1)
        current = :counters.get(call_count, 1)

        case {current, cursor} do
          {1, nil} ->
            {:ok, %{items: ["a", "b"], next_cursor: "cursor_1"}}

          {2, "cursor_1"} ->
            {:ok, %{items: ["c", "d"], next_cursor: "cursor_2"}}

          {3, "cursor_2"} ->
            {:ok, %{items: ["e"], next_cursor: nil}}
        end
      end

      result = Stream.paginate(fetch_fn) |> Enum.to_list()

      assert result == ["a", "b", "c", "d", "e"]
      assert :counters.get(call_count, 1) == 3
    end

    test "returns empty list when first page has no items" do
      fetch_fn = fn nil ->
        {:ok, %{items: [], next_cursor: nil}}
      end

      result = Stream.paginate(fetch_fn) |> Enum.to_list()

      assert result == []
    end

    test "returns empty list from multiple pages with no items" do
      call_count = :counters.new(1, [:atomics])

      fetch_fn = fn cursor ->
        :counters.add(call_count, 1, 1)
        current = :counters.get(call_count, 1)

        case {current, cursor} do
          {1, nil} ->
            {:ok, %{items: [], next_cursor: "cursor_1"}}

          {2, "cursor_1"} ->
            {:ok, %{items: [], next_cursor: nil}}
        end
      end

      result = Stream.paginate(fetch_fn) |> Enum.to_list()

      assert result == []
      assert :counters.get(call_count, 1) == 2
    end

    test "lazily fetches pages - only fetches pages as needed" do
      call_count = :counters.new(1, [:atomics])

      fetch_fn = fn cursor ->
        :counters.add(call_count, 1, 1)
        current = :counters.get(call_count, 1)

        case {current, cursor} do
          {1, nil} ->
            {:ok, %{items: [1, 2, 3], next_cursor: "cursor_1"}}

          {2, "cursor_1"} ->
            {:ok, %{items: [4, 5, 6], next_cursor: "cursor_2"}}

          {3, "cursor_2"} ->
            {:ok, %{items: [7, 8, 9], next_cursor: nil}}
        end
      end

      # Take only 4 items - should only need 2 pages
      result = Stream.paginate(fetch_fn) |> Enum.take(4)

      assert result == [1, 2, 3, 4]
      assert :counters.get(call_count, 1) == 2
    end

    test "raises error when fetch_fn returns error on first page" do
      error = Error.unauthorized("Invalid credentials")

      fetch_fn = fn nil ->
        {:error, error}
      end

      stream = Stream.paginate(fetch_fn)

      assert_raise Error, "Invalid credentials", fn ->
        Enum.to_list(stream)
      end
    end

    test "raises error when fetch_fn returns error on subsequent page" do
      call_count = :counters.new(1, [:atomics])
      error = Error.rate_limited("Too many requests", 60)

      fetch_fn = fn cursor ->
        :counters.add(call_count, 1, 1)
        current = :counters.get(call_count, 1)

        case {current, cursor} do
          {1, nil} ->
            {:ok, %{items: [1, 2, 3], next_cursor: "cursor_1"}}

          {2, "cursor_1"} ->
            {:error, error}
        end
      end

      stream = Stream.paginate(fetch_fn)

      assert_raise Error, "Too many requests", fn ->
        Enum.to_list(stream)
      end

      # Should have made 2 calls before error
      assert :counters.get(call_count, 1) == 2
    end

    test "yields single item from single page" do
      fetch_fn = fn nil ->
        {:ok, %{items: [:single], next_cursor: nil}}
      end

      result = Stream.paginate(fetch_fn) |> Enum.to_list()

      assert result == [:single]
    end

    test "works with complex items (maps/structs)" do
      items = [
        %{id: "1", name: "first"},
        %{id: "2", name: "second"}
      ]

      fetch_fn = fn nil ->
        {:ok, %{items: items, next_cursor: nil}}
      end

      result = Stream.paginate(fetch_fn) |> Enum.to_list()

      assert result == items
    end

    test "can be composed with other stream operations" do
      fetch_fn = fn cursor ->
        case cursor do
          nil -> {:ok, %{items: [1, 2, 3, 4, 5], next_cursor: "page2"}}
          "page2" -> {:ok, %{items: [6, 7, 8, 9, 10], next_cursor: nil}}
        end
      end

      result =
        Stream.paginate(fetch_fn)
        |> Elixir.Stream.filter(&(rem(&1, 2) == 0))
        |> Elixir.Stream.map(&(&1 * 2))
        |> Enum.to_list()

      assert result == [4, 8, 12, 16, 20]
    end

    test "handles error after partial consumption" do
      call_count = :counters.new(1, [:atomics])

      fetch_fn = fn cursor ->
        :counters.add(call_count, 1, 1)
        current = :counters.get(call_count, 1)

        case {current, cursor} do
          {1, nil} ->
            {:ok, %{items: [1, 2], next_cursor: "cursor_1"}}

          {2, "cursor_1"} ->
            {:ok, %{items: [3, 4], next_cursor: "cursor_2"}}

          {3, "cursor_2"} ->
            {:error, Error.server_error("Database error", 500)}
        end
      end

      stream = Stream.paginate(fetch_fn)

      # First 4 items should work
      assert Enum.take(stream, 4) == [1, 2, 3, 4]
    end
  end
end
