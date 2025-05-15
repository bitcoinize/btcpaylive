defmodule BtcpayTracker.Webhooks.InvoiceCreatedPayload do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :type, :string
    field :deliveryId, :string
    field :webhookId, :string
    field :originalDeliveryId, :string
    field :isRedelivery, :boolean
    field :timestamp, :integer
    field :storeId, :string
    field :invoiceId, :string
    field :metadata, :map # Capture all metadata, specific fields like orderId can be extracted later
    # Add other fields from InvoiceCreated payload as needed, e.g., amount, currency, if directly available
  end

  def changeset(data) do
    %__MODULE__{}
    |> cast(data, [
      :type,
      :deliveryId,
      :webhookId,
      :originalDeliveryId,
      :isRedelivery,
      :timestamp,
      :storeId,
      :invoiceId,
      :metadata
    ])
    |> validate_required([:type, :invoiceId, :timestamp])
    |> validate_inclusion(:type, ["InvoiceCreated"])
  end
end 