defmodule BtcpayTracker.Repo.Migrations.UpdateTransactionsForMultiWebhooks do
  use Ecto.Migration

  def change do
    alter table(:transactions) do
      # Modify status default
      modify :status, :string, default: "pending", from: fragment("'settled'")

      # Add new timestamp fields
      add :created_at_webhook_timestamp, :utc_datetime
      add :payment_settled_at_webhook_timestamp, :utc_datetime, null: true # Can be null if payment settles with final settlement
      add :final_settled_at_webhook_timestamp, :utc_datetime, null: true # Can be null until fully settled

      # Add new raw payload fields
      add :raw_payload_created, :map
      add :raw_payload_payment_settled, :map, null: true
      add :raw_payload_settled, :map, null: true

      # Rename old fields (or remove and add, depending on preference/complexity)
      # For simplicity here, we'll remove old `settled_at` and `raw_payload`.
      # Ensure data migration if necessary in a real-world scenario.
      remove :settled_at
      remove :raw_payload
    end

    # Ensure received_at exists (it should from the previous migration)
    # If it might not, an `alter table(:transactions) do add_if_not_exists ... end` approach could be used or a separate migration.
  end
end
