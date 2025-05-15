defmodule BtcpayTrackerWeb.Router do
  use BtcpayTrackerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BtcpayTrackerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", BtcpayTrackerWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/dashboard", DashboardLive
  end

  scope "/api", BtcpayTrackerWeb do
    pipe_through :api
    post "/webhooks/btcpay/events", WebhookController, :handle_event
  end

  # Other scopes may use custom stacks.
  # scope "/api", BtcpayTrackerWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Mix.env() == :dev do
    scope "/dev" do
      pipe_through :browser
    end
  end
end
