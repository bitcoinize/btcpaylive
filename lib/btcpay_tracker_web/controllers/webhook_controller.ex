defmodule BtcpayTrackerWeb.WebhookController do
  use BtcpayTrackerWeb, :controller
  require Logger
  alias BtcpayTracker.Ingestion

  # New generic event handler
  def handle_event(conn, _params) do
    secret = System.get_env("BTCPAY_WEBHOOK_SECRET")

    unless secret do
      Logger.error("BTCPAY_WEBHOOK_SECRET not configured.")
      conn
      |> put_status(:internal_server_error)
      |> json(%{error: "Webhook secret not configured."})
    else
      case get_req_header(conn, "btcpay-sig") do
        [signature_header | _tail] ->
          if Mix.env() == :dev do
            Logger.debug("Received BTCPAY-SIG header: #{signature_header}")
          end

          raw_body = conn.assigns[:raw_body]

          unless raw_body do
            Logger.error("Raw body not found in conn.assigns. Ensure Plug.Parsers/CacheBodyReader is configured correctly.")
            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "Internal server error processing webhook."})
          else
            parts = String.split(signature_header, "=")

            if length(parts) == 2 && hd(parts) == "sha256" do
              expected_hash = tl(parts) |> hd()
              calculated_hash =
                :crypto.mac(:hmac, :sha256, secret, raw_body)
                |> Base.encode16(case: :lower)

              if Plug.Crypto.secure_compare(expected_hash, calculated_hash) do
                Logger.info("BTCPAY-SIG validation successful. Determining event type.")

                # Determine event type and delegate
                case Jason.decode(raw_body) do
                  {:ok, %{"type" => event_type} = decoded_json_map} ->
                    Logger.info("Webhook event type: #{event_type}")
                    Task.Supervisor.async_nolink(BtcpayTracker.TaskSupervisor, fn ->
                      Ingestion.process_event(event_type, decoded_json_map, raw_body)
                    end)

                    conn
                    |> put_status(:accepted)
                    |> json(%{status: "accepted", message: "Webhook received and queued for processing."})

                  {:ok, other_payload} ->
                    Logger.warning("Webhook payload is missing 'type' field or is not a map: #{inspect(other_payload)}")
                    conn
                    |> put_status(:bad_request)
                    |> json(%{error: "Invalid webhook payload: missing 'type' field."})

                  {:error, Jason.DecodeError} = error ->
                    Logger.error("Failed to decode JSON payload for event type determination: #{inspect(error)}. Raw body: #{raw_body}")
                    conn
                    |> put_status(:bad_request)
                    |> json(%{error: "Invalid JSON payload."})
                end
              else
                Logger.warning(
                  "BTCPAY-SIG validation failed. Expected: #{expected_hash}, Calculated: #{calculated_hash}"
                )
                conn
                |> put_status(:forbidden)
                |> json(%{error: "Webhook signature validation failed."})
              end
            else
              Logger.warning("Invalid BTCPAY-SIG header format: #{signature_header}")
              conn
              |> put_status(:bad_request)
              |> json(%{error: "Invalid BTCPAY-SIG header format."})
            end
          end

        [] ->
          Logger.warning("Missing BTCPAY-SIG header.")
          conn
          |> put_status(:unauthorized)
          |> json(%{error: "Missing BTCPAY-SIG header."})
      end
    end
  end
end 