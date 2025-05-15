defmodule BtcpayTracker.Repo.Migrations.AddStoreIdToTransactions do
  use Ecto.Migration

  def change do
    alter table(:transactions) do
      add :store_id, :string, null: true # Allow null initially, can be backfilled or populated by InvoiceCreated
    end

    create index(:transactions, [:store_id])
  end
end
