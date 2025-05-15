defmodule BtcpayTracker.Webhooks.InvoicePaymentSettledPayload do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :type, :string
    field :deliveryId, :string
    field :webhookId, :string
    field :originalDeliveryId, :string
    field :isRedelivery, :boolean
    field :timestamp, :integer # This timestamp reflects when the payment settled
    field :storeId, :string
    field :invoiceId, :string
    field :afterExpiration, :boolean
    field :paymentMethod, :string # e.g., "BTC-LightningNetwork", "BTC-OnChain"
    field :payment, :map # Contains id, receivedDate, value, fee, status, destination
    field :metadata, :map # Optional metadata
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
      :afterExpiration,
      :paymentMethod,
      :payment,
      :metadata
    ])
    |> validate_required([:type, :invoiceId, :timestamp, :paymentMethod, :payment])
    |> validate_inclusion(:type, ["InvoicePaymentSettled"])
    |> validate_payment_details()
  end

  defp validate_payment_details(changeset) do
    payment_map = get_field(changeset, :payment)
    if payment_map && Map.get(payment_map, "value") && Map.get(payment_map, "status") == "Settled" do
      changeset
    else
      add_error(changeset, :payment, "Payment details must include a 'value' and status 'Settled' for InvoicePaymentSettled events.")
    end
  end
end 