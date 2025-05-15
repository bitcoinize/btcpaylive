defmodule BtcpayTracker.Repo.Migrations.CreateTransactionsTable do
  use Ecto.Migration

  def change do
    create table(:transactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :btcpay_invoice_id, :text, null: false
      add :btcpay_order_id, :text, null: true
      add :status, :text, null: false
      add :amount_crypto, :decimal, null: false
      add :currency_crypto, :text, null: false
      add :amount_fiat, :decimal, null: false
      add :currency_fiat, :text, null: false
      add :payment_method, :text, null: true # Can be derived, might not always be there at initial insert
      add :settled_at, :utc_datetime, null: false
      add :received_at, :utc_datetime, null: false
      add :raw_payload, :jsonb, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:transactions, [:btcpay_invoice_id], unique: true)
  end
end
