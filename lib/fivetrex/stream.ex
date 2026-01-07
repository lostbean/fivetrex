defmodule Fivetrex.Stream do
  @moduledoc """
  Utilities for cursor-based pagination as Elixir Streams.

  Fivetran's REST API uses cursor-based pagination for list endpoints. This module
  provides utilities to transparently handle pagination, allowing you to iterate
  over all results as a lazy Elixir Stream without loading everything into memory.

  ## How It Works

  When you call a streaming function like `Fivetrex.Groups.stream/2`, this module:

  1. Fetches the first page of results
  2. Yields each item from the page
  3. If there's a `next_cursor`, automatically fetches the next page
  4. Continues until all pages are exhausted

  Because Elixir Streams are lazy, pages are only fetched as needed. If you
  `Enum.take(5)` from a stream, only enough pages to provide 5 items are fetched.

  ## Example

      # Stream through all groups, processing one at a time
      Fivetrex.Groups.stream(client)
      |> Stream.filter(&(&1.name =~ "production"))
      |> Enum.each(fn group ->
        IO.puts("Found production group: \#{group.name}")
      end)

      # Take only the first 10 broken connectors
      # (stops fetching pages once 10 are found)
      Fivetrex.Connectors.stream(client, group_id)
      |> Stream.filter(fn c -> c.status["sync_state"] == "broken" end)
      |> Enum.take(10)

  ## Memory Efficiency

  Unlike `Enum.flat_map/2` which loads all results into memory, streams process
  items one at a time. This makes it safe to iterate over thousands or millions
  of resources:

      # Memory-efficient: processes one connector at a time
      Fivetrex.Groups.stream(client)
      |> Stream.flat_map(fn group ->
        Fivetrex.Connectors.stream(client, group.id)
      end)
      |> Enum.each(&process_connector/1)

  ## Error Handling

  If an API error occurs during pagination, the error is raised as an exception.
  Wrap stream operations in `try/rescue` if you need to handle errors:

      try do
        Fivetrex.Groups.stream(client)
        |> Enum.to_list()
      rescue
        e in Fivetrex.Error ->
          Logger.error("Failed to fetch groups: \#{e.message}")
          []
      end

  """

  @doc """
  Creates a stream that handles cursor-based pagination.

  This function is used internally by API modules to implement streaming.
  You typically won't call it directly - use functions like
  `Fivetrex.Groups.stream/2` instead.

  ## Parameters

    * `fetch_fn` - A function that takes a cursor (or `nil` for the first page)
      and returns `{:ok, %{items: items, next_cursor: cursor}}` or `{:error, error}`

  ## Returns

  An `Enumerable.t()` that yields items from all pages.

  ## Examples

      # This is how Groups.stream/2 is implemented internally
      def stream(client, opts \\\\ []) do
        Fivetrex.Stream.paginate(fn cursor ->
          list(client, Keyword.put(opts, :cursor, cursor))
        end)
      end

  ## Raises

    * `Fivetrex.Error` - If the fetch function returns an error

  """
  @spec paginate((String.t() | nil ->
                    {:ok, %{items: list(), next_cursor: String.t() | nil}} | {:error, any()})) ::
          Enumerable.t()
  def paginate(fetch_fn) do
    Stream.resource(
      fn -> {:continue, nil} end,
      fn
        :halt ->
          {:halt, :done}

        {:continue, cursor} ->
          case fetch_fn.(cursor) do
            {:ok, %{items: items, next_cursor: nil}} ->
              {items, :halt}

            {:ok, %{items: items, next_cursor: next_cursor}} ->
              {items, {:continue, next_cursor}}

            {:error, error} ->
              raise error
          end
      end,
      fn _ -> :ok end
    )
  end
end
