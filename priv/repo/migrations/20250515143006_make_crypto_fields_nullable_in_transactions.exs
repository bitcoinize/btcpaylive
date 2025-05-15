defmodule BtcpayTracker.Repo.Migrations.MakeCryptoFieldsNullableInTransactions do
  use Ecto.Migration

  def change do
    alter table(:transactions) do
      modify :amount_crypto, :decimal, null: true
      modify :currency_crypto, :text, null: true
    end
  end
end
