defmodule Fivetrex.Groups do
  @moduledoc """
  Functions for managing Fivetran Groups.

  A Group is a logical container that holds multiple connectors and maps to a
  specific destination schema or database. Groups are the top-level organizational
  unit in Fivetran's resource hierarchy.

  ## Overview

  Groups serve as containers for organizing related connectors. Each group is
  associated with a single destination (data warehouse) and can contain multiple
  connectors that load data into that destination.

  ## Common Operations

  ### Listing Groups

      {:ok, %{items: groups, next_cursor: cursor}} = Fivetrex.Groups.list(client)

  ### Getting a Group

      {:ok, group} = Fivetrex.Groups.get(client, "group_id")

  ### Creating a Group

      {:ok, group} = Fivetrex.Groups.create(client, %{name: "Production Data"})

  ### Updating a Group

      {:ok, group} = Fivetrex.Groups.update(client, "group_id", %{name: "New Name"})

  ### Deleting a Group

      :ok = Fivetrex.Groups.delete(client, "group_id")

  ## Streaming

  For iterating over all groups without loading them into memory:

      client
      |> Fivetrex.Groups.stream()
      |> Stream.filter(&String.contains?(&1.name, "prod"))
      |> Enum.each(&IO.inspect/1)

  ## See Also

    * `Fivetrex.Models.Group` - The Group struct
    * `Fivetrex.Connectors` - Managing connectors within groups
    * `Fivetrex.Destinations` - Managing destinations for groups
  """

  alias Fivetrex.Client
  alias Fivetrex.Models.Group

  @doc """
  Lists all groups accessible to your account.

  Returns a paginated list of groups. Use the `next_cursor` from the response
  to fetch the next page, or use `stream/2` for automatic pagination.

  ## Options

    * `:cursor` - Pagination cursor from a previous response's `next_cursor`.
      Pass `nil` or omit for the first page.

    * `:limit` - Maximum number of groups to return per page. Defaults to Fivetran's
      default (usually 100). Maximum is 1000.

  ## Returns

    * `{:ok, %{items: [Group.t()], next_cursor: String.t() | nil}}` - A map containing:
      * `:items` - List of `%Fivetrex.Models.Group{}` structs
      * `:next_cursor` - Cursor for the next page, or `nil` if this is the last page

    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

  Fetch the first page:

      {:ok, %{items: groups, next_cursor: cursor}} = Fivetrex.Groups.list(client)

  Fetch the next page using a cursor:

      {:ok, %{items: more_groups, next_cursor: next}} =
        Fivetrex.Groups.list(client, cursor: cursor)

  Limit results per page:

      {:ok, result} = Fivetrex.Groups.list(client, limit: 50)

  """
  @spec list(Client.t(), keyword()) ::
          {:ok, %{items: [Group.t()], next_cursor: String.t() | nil}}
          | {:error, Fivetrex.Error.t()}
  def list(client, opts \\ []) do
    params = build_pagination_params(opts)

    case Client.get(client, "/groups", params: params) do
      {:ok, %{"data" => %{"items" => items, "next_cursor" => next_cursor}}} ->
        groups = Enum.map(items, &Group.from_map/1)
        {:ok, %{items: groups, next_cursor: next_cursor}}

      {:ok, %{"data" => %{"items" => items}}} ->
        groups = Enum.map(items, &Group.from_map/1)
        {:ok, %{items: groups, next_cursor: nil}}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Returns a stream of all groups, handling pagination automatically.

  This function returns an Elixir `Stream` that lazily fetches pages as needed.
  It's memory-efficient for iterating over large numbers of groups.

  ## Options

    * `:limit` - Number of items per page (passed to each API call)

  ## Returns

  An `Enumerable.t()` that yields `%Fivetrex.Models.Group{}` structs.

  ## Examples

  Stream all groups:

      Fivetrex.Groups.stream(client)
      |> Enum.each(fn group ->
        IO.puts("Group: \#{group.name}")
      end)

  Filter and collect:

      production_groups =
        Fivetrex.Groups.stream(client)
        |> Stream.filter(&String.contains?(&1.name, "prod"))
        |> Enum.to_list()

  Take first 5:

      first_five = Fivetrex.Groups.stream(client) |> Enum.take(5)

  ## Error Handling

  If an API error occurs during streaming, a `Fivetrex.Error` is raised.
  Use `try/rescue` to handle errors:

      try do
        Fivetrex.Groups.stream(client) |> Enum.to_list()
      rescue
        e in Fivetrex.Error ->
          Logger.error("Failed: \#{e.message}")
          []
      end

  """
  @spec stream(Client.t(), keyword()) :: Enumerable.t()
  def stream(client, opts \\ []) do
    Fivetrex.Stream.paginate(fn cursor ->
      list(client, Keyword.put(opts, :cursor, cursor))
    end)
  end

  @doc """
  Gets a group by its ID.

  ## Parameters

    * `client` - The Fivetrex client
    * `group_id` - The unique identifier of the group

  ## Returns

    * `{:ok, Group.t()}` - The group as a `%Fivetrex.Models.Group{}` struct
    * `{:error, Fivetrex.Error.t()}` - On failure (e.g., `:not_found` if ID is invalid)

  ## Examples

      {:ok, group} = Fivetrex.Groups.get(client, "decent_dropsy")
      IO.puts("Group name: \#{group.name}")

  Handle not found:

      case Fivetrex.Groups.get(client, "invalid_id") do
        {:ok, group} -> group
        {:error, %Fivetrex.Error{type: :not_found}} -> nil
      end

  """
  @spec get(Client.t(), String.t()) :: {:ok, Group.t()} | {:error, Fivetrex.Error.t()}
  def get(client, group_id) do
    case Client.get(client, "/groups/#{group_id}") do
      {:ok, %{"data" => data}} ->
        {:ok, Group.from_map(data)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Creates a new group.

  ## Parameters

    * `client` - The Fivetrex client
    * `params` - A map with group parameters:
      * `:name` - Required. The name of the group.

  ## Returns

    * `{:ok, Group.t()}` - The created group
    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

      {:ok, group} = Fivetrex.Groups.create(client, %{name: "My Analytics Warehouse"})
      IO.puts("Created group with ID: \#{group.id}")

  """
  @spec create(Client.t(), map()) :: {:ok, Group.t()} | {:error, Fivetrex.Error.t()}
  def create(client, params) do
    case Client.post(client, "/groups", params) do
      {:ok, %{"data" => data}} ->
        {:ok, Group.from_map(data)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Updates an existing group.

  ## Parameters

    * `client` - The Fivetrex client
    * `group_id` - The ID of the group to update
    * `params` - A map with fields to update:
      * `:name` - The new name of the group

  ## Returns

    * `{:ok, Group.t()}` - The updated group
    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

      {:ok, group} = Fivetrex.Groups.update(client, "decent_dropsy", %{
        name: "Production Analytics"
      })

  """
  @spec update(Client.t(), String.t(), map()) :: {:ok, Group.t()} | {:error, Fivetrex.Error.t()}
  def update(client, group_id, params) do
    case Client.patch(client, "/groups/#{group_id}", params) do
      {:ok, %{"data" => data}} ->
        {:ok, Group.from_map(data)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Deletes a group.

  **Warning:** Deleting a group will also delete all connectors within it.
  This operation cannot be undone.

  ## Parameters

    * `client` - The Fivetrex client
    * `group_id` - The ID of the group to delete

  ## Returns

    * `:ok` - On successful deletion
    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

      :ok = Fivetrex.Groups.delete(client, "old_group_id")

  """
  @spec delete(Client.t(), String.t()) :: :ok | {:error, Fivetrex.Error.t()}
  def delete(client, group_id) do
    case Client.delete(client, "/groups/#{group_id}") do
      {:ok, _} ->
        :ok

      {:error, _} = error ->
        error
    end
  end

  defp build_pagination_params(opts) do
    []
    |> maybe_add_param(:cursor, opts[:cursor])
    |> maybe_add_param(:limit, opts[:limit])
  end

  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, value), do: [{key, value} | params]
end
