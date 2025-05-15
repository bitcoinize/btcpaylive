defmodule BtcpayTracker.Repo do
  use Ecto.Repo,
    otp_app: :btcpay_tracker,
    adapter: Ecto.Adapters.Postgres
end
