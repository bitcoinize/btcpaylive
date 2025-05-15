defmodule BtcpayTracker.Webhooks.InvoiceSettledPayload do
  @moduledoc """
  Represents the expected structure of an InvoiceSettled webhook payload from BTCPayServer.
  """
  use Ecto.Schema # Using Ecto.Schema for its casting/validation capabilities, though not an Ecto table
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :type, :string
    field :deliveryId, :string
    field :webhookId, :string
    field :originalDeliveryId, :string
    field :isRedelivery, :boolean
    field :timestamp, :integer # This timestamp reflects when the invoice is fully settled
    field :storeId, :string
    field :invoiceId, :string
    field :metadata, :map # Optional metadata, might contain final fiat values
    field :manuallyMarked, :boolean # Field from example
    field :overPaid, :boolean # Field from example
  end

  def changeset(data) do
    # Ensure data is a map before casting, as it comes from decoded JSON
    data_map = if is_binary(data), do: Jason.decode!(data), else: data
    
    %__MODULE__{}
    |> cast(data_map, [
      :type,
      :deliveryId,
      :webhookId,
      :originalDeliveryId,
      :isRedelivery,
      :timestamp,
      :storeId,
      :invoiceId,
      :metadata,
      :manuallyMarked,
      :overPaid
    ])
    |> validate_required([:type, :invoiceId, :timestamp])
    |> validate_inclusion(:type, ["InvoiceSettled"])
  end

  @doc """
  Parses the raw webhook body (JSON string) into an InvoiceSettledPayload struct.
  """
  def parse_json(json_string) do
    case Jason.decode(json_string) do
      {:ok, params} ->
        changeset(params) # Use the changeset for casting and initial validation
        |> Ecto.Changeset.apply_changes() # Apply changes to get the struct
        |> (&({:ok, &1})).() # Wrap in {:ok, struct}
      {:error, reason} ->
        {:error, "JSON decoding error: #{inspect(reason)}"}
    end
  end
end 