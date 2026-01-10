defmodule Fivetrex.Models.Webhook do
  @moduledoc """
  Represents a Fivetran Webhook.

  Webhooks provide real-time notifications about Fivetran events such as sync
  starts, completions, and failures. Webhooks can be configured at either the
  account level (all connectors) or group level (specific group's connectors).

  ## Fields

    * `:id` - The unique identifier for the webhook
    * `:type` - Webhook scope: `"account"` or `"group"`
    * `:group_id` - Group ID (only for group-level webhooks)
    * `:url` - Endpoint URL where webhook events are delivered
    * `:events` - List of event types that trigger this webhook
    * `:active` - Whether the webhook is actively sending events
    * `:secret` - Secret string for HMAC signature verification (masked in responses)
    * `:created_at` - DateTime of creation (parsed from ISO 8601)
    * `:created_by` - User ID who created the webhook

  ## Webhook Types

    * `"account"` - Receives events for all connectors in your Fivetran account
    * `"group"` - Receives events only for connectors in the specified group

  ## Event Types

  Common events include:

    * `"sync_start"` - Connector sync started
    * `"sync_end"` - Connector sync completed (success or failure)
    * `"status"` - Connector status changed
    * `"dbt_run_start"` - dbt transformation started
    * `"dbt_run_succeeded"` - dbt transformation succeeded
    * `"dbt_run_failed"` - dbt transformation failed

  ## Security

  When creating webhooks with a secret, Fivetran signs each payload using
  HMAC-SHA256. Use `Fivetrex.WebhookSignature.verify/3` to validate incoming
  requests are authentically from Fivetran.

  ## Helper Functions

  This module provides helper functions to check webhook scope:

      if Webhook.account_level?(webhook) do
        IO.puts("Account-wide webhook")
      end

      if Webhook.group_level?(webhook) do
        IO.puts("Group webhook for: \#{webhook.group_id}")
      end

  ## Examples

  Working with webhooks:

      {:ok, webhooks} = Fivetrex.Webhooks.list(client)
      account_webhooks = Enum.filter(webhooks.items, &Webhook.account_level?/1)
      group_webhooks = Enum.filter(webhooks.items, &Webhook.group_level?/1)

  ## See Also

    * `Fivetrex.Webhooks` - API functions for managing webhooks
    * `Fivetrex.WebhookSignature` - Signature verification for incoming webhooks
    * `Fivetrex.Models.WebhookEvent` - Struct for incoming webhook event payloads
  """

  @typedoc """
  A Fivetran Webhook struct.

  All fields may be `nil` if not provided in the API response.
  """
  @type t :: %__MODULE__{
          id: String.t() | nil,
          type: String.t() | nil,
          group_id: String.t() | nil,
          url: String.t() | nil,
          events: [String.t()] | nil,
          active: boolean() | nil,
          secret: String.t() | nil,
          created_at: DateTime.t() | nil,
          created_by: String.t() | nil
        }

  defstruct [
    :id,
    :type,
    :group_id,
    :url,
    :events,
    :active,
    :secret,
    :created_at,
    :created_by
  ]

  @doc """
  Converts a map (from JSON response) to a Webhook struct.

  This function is used internally by `Fivetrex.Webhooks` functions to parse
  API responses into typed structs.

  ## Parameters

    * `map` - A map with string keys from a decoded JSON response

  ## Returns

  A `%Fivetrex.Models.Webhook{}` struct with fields populated from the map.

  ## Examples

      iex> map = %{"id" => "wh_123", "type" => "account", "active" => true}
      iex> webhook = Fivetrex.Models.Webhook.from_map(map)
      iex> webhook.type
      "account"

  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      type: map["type"],
      group_id: map["group_id"],
      url: map["url"],
      events: map["events"],
      active: map["active"],
      secret: map["secret"],
      created_at: parse_datetime(map["created_at"]),
      created_by: map["created_by"]
    }
  end

  # Private helper to parse datetime values
  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = dt), do: dt

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _} -> nil
    end
  end

  defp parse_datetime(_), do: nil

  @doc """
  Returns true if this is an account-level webhook.

  Account-level webhooks receive events for all connectors in the Fivetran account.

  ## Parameters

    * `webhook` - A `%Fivetrex.Models.Webhook{}` struct

  ## Returns

    * `true` - If the webhook type is `"account"`
    * `false` - Otherwise

  ## Examples

      iex> webhook = %Fivetrex.Models.Webhook{type: "account"}
      iex> Fivetrex.Models.Webhook.account_level?(webhook)
      true

      iex> webhook = %Fivetrex.Models.Webhook{type: "group"}
      iex> Fivetrex.Models.Webhook.account_level?(webhook)
      false

  """
  @spec account_level?(t()) :: boolean()
  def account_level?(%__MODULE__{type: type}), do: type == "account"

  @doc """
  Returns true if this is a group-level webhook.

  Group-level webhooks receive events only for connectors in the specified group.

  ## Parameters

    * `webhook` - A `%Fivetrex.Models.Webhook{}` struct

  ## Returns

    * `true` - If the webhook type is `"group"`
    * `false` - Otherwise

  ## Examples

      iex> webhook = %Fivetrex.Models.Webhook{type: "group", group_id: "g_123"}
      iex> Fivetrex.Models.Webhook.group_level?(webhook)
      true

      iex> webhook = %Fivetrex.Models.Webhook{type: "account"}
      iex> Fivetrex.Models.Webhook.group_level?(webhook)
      false

  """
  @spec group_level?(t()) :: boolean()
  def group_level?(%__MODULE__{type: type}), do: type == "group"
end
