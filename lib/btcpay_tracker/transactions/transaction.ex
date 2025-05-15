defmodule BtcpayTracker.Transactions.Transaction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "transactions" do
    field :btcpay_invoice_id, :string
    field :btcpay_order_id, :string
    field :store_id, :string # New field for Store ID
    field :status, :string, default: "pending" # New default: pending
    field :amount_crypto, :decimal
    field :currency_crypto, :string
    field :amount_fiat, :decimal
    field :currency_fiat, :string
    field :payment_method, :string
    field :received_at, :utc_datetime # Timestamp when the first webhook for this invoice was received

    # New timestamp fields
    field :created_at_webhook_timestamp, :utc_datetime # From InvoiceCreated timestamp
    field :payment_settled_at_webhook_timestamp, :utc_datetime # From InvoicePaymentSettled timestamp
    field :final_settled_at_webhook_timestamp, :utc_datetime # From InvoiceSettled timestamp

    # New raw payload fields
    field :raw_payload_created, :map
    field :raw_payload_payment_settled, :map
    field :raw_payload_settled, :map

    timestamps(type: :utc_datetime) # Adds inserted_at and updated_at
  end

  @doc false
  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [
      :btcpay_invoice_id,
      :btcpay_order_id,
      :store_id, # Add store_id to cast
      :status,
      :amount_crypto,
      :currency_crypto,
      :amount_fiat,
      :currency_fiat,
      :payment_method,
      :received_at,
      :created_at_webhook_timestamp,
      :payment_settled_at_webhook_timestamp,
      :final_settled_at_webhook_timestamp,
      :raw_payload_created,
      :raw_payload_payment_settled,
      :raw_payload_settled
    ])
    |> validate_required([
      :btcpay_invoice_id,
      :status,
      :received_at
      # Other fields are populated incrementally or might be nullable initially
    ])
    |> unique_constraint(:btcpay_invoice_id)
  end

  def update_changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [
      # Fields that can be updated by subsequent webhooks
      :btcpay_order_id, # Could potentially be in multiple webhooks
      :store_id, # Add store_id here if it can be updated by other events (e.g. if missing from InvoiceCreated but present elsewhere)
      :status,
      :amount_crypto,
      :currency_crypto,
      :amount_fiat, # May be refined by later webhooks
      :currency_fiat, # May be refined by later webhooks
      :payment_method,
      :payment_settled_at_webhook_timestamp,
      :final_settled_at_webhook_timestamp,
      :raw_payload_payment_settled,
      :raw_payload_settled
      # created_at_webhook_timestamp and raw_payload_created are set once
      # received_at is set once
    ])
    |> validate_required([:status]) # Status is always required for an update
  end
end 