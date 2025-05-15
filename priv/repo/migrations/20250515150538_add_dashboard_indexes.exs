defmodule BtcpayTracker.Repo.Migrations.AddDashboardIndexes do
  use Ecto.Migration

  def change do
    create index(:transactions, [:status])
    create index(:transactions, [:payment_method])
    create index(:transactions, [:currency_fiat])
    create index(:transactions, [:currency_crypto])
    create index(:transactions, [:final_settled_at_webhook_timestamp])
  end
end
