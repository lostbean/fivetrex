defmodule Fivetrex.Models.Group do
  @moduledoc """
  Represents a Fivetran Group.

  A Group is the top-level organizational unit in Fivetran's resource hierarchy.
  It serves as a logical container that holds multiple connectors and maps to a
  specific destination schema or database.

  ## Fields

    * `:id` - The unique identifier for the group (e.g., `"decent_dropsy"`)
    * `:name` - The display name of the group
    * `:created_at` - ISO 8601 timestamp of when the group was created

  ## Structure

  Groups have a one-to-one relationship with destinations and a one-to-many
  relationship with connectors:

  ```
  Group
  ├── Destination (exactly one)
  └── Connectors (zero or more)
  ```

  ## Examples

  Working with a group struct:

      {:ok, group} = Fivetrex.Groups.get(client, "decent_dropsy")
      IO.puts("Group: \#{group.name} (ID: \#{group.id})")
      IO.puts("Created: \#{group.created_at}")

  Pattern matching:

      case Fivetrex.Groups.get(client, group_id) do
        {:ok, %Fivetrex.Models.Group{name: name}} ->
          IO.puts("Found group: \#{name}")

        {:error, _} ->
          IO.puts("Group not found")
      end

  ## See Also

    * `Fivetrex.Groups` - API functions for managing groups
    * `Fivetrex.Models.Connector` - Connectors that belong to groups
    * `Fivetrex.Models.Destination` - Destinations associated with groups
  """

  @typedoc """
  A Fivetran Group struct.

  All fields may be `nil` if not provided in the API response.
  """
  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          created_at: String.t() | nil
        }

  defstruct [:id, :name, :created_at]

  @doc """
  Converts a map (from JSON response) to a Group struct.

  This function is used internally by `Fivetrex.Groups` functions to parse
  API responses into typed structs.

  ## Parameters

    * `map` - A map with string keys from a decoded JSON response

  ## Returns

  A `%Fivetrex.Models.Group{}` struct with fields populated from the map.

  ## Examples

      iex> map = %{"id" => "abc123", "name" => "Production", "created_at" => "2024-01-15T10:30:00Z"}
      iex> Fivetrex.Models.Group.from_map(map)
      %Fivetrex.Models.Group{id: "abc123", name: "Production", created_at: "2024-01-15T10:30:00Z"}

      iex> Fivetrex.Models.Group.from_map(%{})
      %Fivetrex.Models.Group{id: nil, name: nil, created_at: nil}

  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      name: map["name"],
      created_at: map["created_at"]
    }
  end
end
