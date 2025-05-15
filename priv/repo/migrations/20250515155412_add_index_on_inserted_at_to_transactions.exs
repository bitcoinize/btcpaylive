defmodule BtcpayTracker.Repo.Migrations.AddIndexOnInsertedAtToTransactions do
  use Ecto.Migration

  def change do
    create index(:transactions, [:inserted_at])
  end
end
