defmodule BtcpayTracker.Ingestion do
  alias BtcpayTracker.Repo
  alias BtcpayTracker.Transactions.Transaction
  alias BtcpayTracker.Webhooks.InvoiceCreatedPayload
  alias BtcpayTracker.Webhooks.InvoicePaymentSettledPayload
  alias BtcpayTracker.Webhooks.InvoiceSettledPayload
  alias BtcpayTrackerWeb.Endpoint
  alias BtcpayTracker.ParsingUtils
  require Logger

  @doc """
  Main entry point for processing a webhook event after signature validation.
  Delegates to specific handlers based on the event type.
  `decoded_json_map` is the full payload as a map.
  `raw_body` is the original JSON string for storing.
  """
  def process_event("InvoiceCreated", decoded_json_map, _raw_body) do
    process_invoice_created(decoded_json_map)
  end

  def process_event("InvoicePaymentSettled", decoded_json_map, _raw_body) do
    process_invoice_payment_settled(decoded_json_map)
  end

  def process_event("InvoiceSettled", decoded_json_map, _raw_body) do
    process_invoice_final_settled(decoded_json_map)
  end

  def process_event(event_type, _decoded_json_map, raw_body) do
    Logger.info("Received unhandled webhook event type: #{event_type}. Raw body: #{raw_body}")
    {:ok, :unhandled_event_type, event_type}
  end

  # --- InvoiceCreated Handler ---
  defp process_invoice_created(decoded_json_map) do
    try do
      received_at_utc = DateTime.utc_now() |> DateTime.truncate(:second)

      with {:ok, payload_struct} <- InvoiceCreatedPayload.changeset(decoded_json_map) |> Ecto.Changeset.apply_changes() |> (&({:ok, &1})).() do
        created_at_ts = DateTime.from_unix!(payload_struct.timestamp, :second)
        metadata = payload_struct.metadata || %{}
        order_id = Map.get(metadata, "orderId") || Map.get(metadata, :orderId)
        store_id_from_payload = payload_struct.storeId # Extract storeId from payload

        # Attempt to get initial fiat amount from metadata (posData or receiptData)
        fiat_amount_str = get_in(decoded_json_map, ["metadata", "receiptData", "Total"]) ||
                          get_in(decoded_json_map, ["metadata", "posData", "total"])
        parsed_fiat = ParsingUtils.parse_fiat_string(fiat_amount_str)

        attrs = %{
          btcpay_invoice_id: payload_struct.invoiceId,
          btcpay_order_id: order_id,
          store_id: store_id_from_payload, # Add store_id to attributes
          status: "pending",
          amount_fiat: parsed_fiat.amount,
          currency_fiat: parsed_fiat.currency,
          created_at_webhook_timestamp: created_at_ts,
          received_at: received_at_utc,
          raw_payload_created: decoded_json_map
          # crypto fields, payment_method, etc., will be nil initially
        }

        changeset = Transaction.changeset(%Transaction{}, attrs)

        case Repo.insert(changeset, on_conflict: :nothing, conflict_target: :btcpay_invoice_id) do
          {:ok, transaction} ->
            Logger.info("InvoiceCreated: Successfully created transaction #{transaction.id} for invoice #{payload_struct.invoiceId}")
            broadcast_new_transaction_event(transaction)
            {:ok, :created, transaction}
          {:error, changeset} ->
            # This check is for :nothing on_conflict, which results in action: nil and no error on duplicate
            # However, if other errors occur, they should be logged.
            if changeset.action == nil && Enum.empty?(changeset.errors) do # Successfully ignored duplicate via on_conflict: :nothing
              Logger.info("InvoiceCreated: Duplicate btcpay_invoice_id #{payload_struct.invoiceId} received. Transaction already exists. Ignoring creation.")
              # Fetch the existing transaction to return it, simulating an :ok scenario for the controller
              existing_transaction = Repo.get_by(Transaction, btcpay_invoice_id: payload_struct.invoiceId)
              broadcast_new_transaction_event(existing_transaction)
              {:ok, :duplicate_ignored, existing_transaction}
            else
              Logger.error("InvoiceCreated: Failed to save transaction for invoice #{payload_struct.invoiceId}. Changeset: #{inspect(changeset)}")
              {:error, :database_error, changeset}
            end
        end
      else
        {:error, reason} ->
          Logger.error("InvoiceCreated: Failed to parse payload. Reason: #{inspect(reason)}. Data: #{inspect(decoded_json_map)}")
          {:error, :parsing_failed, reason}
      end
    rescue
      e ->
        Logger.error("InvoiceCreated: Unexpected error for payload #{inspect(decoded_json_map)}. Error: #{inspect(e)}, Stacktrace: #{inspect(__STACKTRACE__)}")
        {:error, :unexpected_error, e}
    end
  end

  # --- InvoicePaymentSettled Handler ---
  defp process_invoice_payment_settled(decoded_json_map) do
    try do
      with {:ok, payload_struct} <- InvoicePaymentSettledPayload.changeset(decoded_json_map) |> Ecto.Changeset.apply_changes() |> (&({:ok, &1})).() do
        payment_settled_ts = DateTime.from_unix!(payload_struct.timestamp, :second)
        payment_details = payload_struct.payment || %{}
        crypto_value_str = Map.get(payment_details, "value")
        # paymentMethod is like "BTC-LightningNetwork" or "BTC"
        # We can derive currency_crypto from paymentMethod string, e.g. take the part before '-'
        currency_crypto_val = ParsingUtils.extract_crypto_currency(payload_struct.paymentMethod)

        case Repo.get_by(Transaction, btcpay_invoice_id: payload_struct.invoiceId) do
          nil ->
            Logger.warning("InvoicePaymentSettled: No existing transaction found for invoice_id #{payload_struct.invoiceId}. Possible missed InvoiceCreated event.")
            # Optionally, create a new record here if desired, or just log and ignore.
            {:error, :not_found, payload_struct.invoiceId}

          transaction ->
            attrs = %{
              status: "processing_payment",
              amount_crypto: ParsingUtils.cast_to_decimal(crypto_value_str),
              currency_crypto: currency_crypto_val,
              payment_method: payload_struct.paymentMethod,
              payment_settled_at_webhook_timestamp: payment_settled_ts,
              raw_payload_payment_settled: decoded_json_map
            }
            changeset = Transaction.update_changeset(transaction, attrs)

            case Repo.update(changeset) do
              {:ok, updated_transaction} ->
                Logger.info("InvoicePaymentSettled: Successfully updated transaction #{updated_transaction.id} for invoice #{payload_struct.invoiceId}")
                broadcast_updated_transaction_event(updated_transaction)
                {:ok, :updated, updated_transaction}
              {:error, changeset} ->
                Logger.error("InvoicePaymentSettled: Failed to update transaction for invoice #{payload_struct.invoiceId}. Changeset: #{inspect(changeset)}")
                {:error, :database_error, changeset}
            end
        end
      else
        {:error, reason} ->
          Logger.error("InvoicePaymentSettled: Failed to parse payload. Reason: #{inspect(reason)}. Data: #{inspect(decoded_json_map)}")
          {:error, :parsing_failed, reason}
      end
    rescue
      e ->
        Logger.error("InvoicePaymentSettled: Unexpected error for payload #{inspect(decoded_json_map)}. Error: #{inspect(e)}, Stacktrace: #{inspect(__STACKTRACE__)}")
        {:error, :unexpected_error, e}
    end
  end

  # --- InvoiceSettled (Final) Handler ---
  defp process_invoice_final_settled(decoded_json_map) do
    try do
      with {:ok, payload_struct} <- InvoiceSettledPayload.changeset(decoded_json_map) |> Ecto.Changeset.apply_changes() |> (&({:ok, &1})).() do
        final_settled_ts = DateTime.from_unix!(payload_struct.timestamp, :second)

        case Repo.get_by(Transaction, btcpay_invoice_id: payload_struct.invoiceId) do
          nil ->
            Logger.warning("InvoiceSettled: No existing transaction found for invoice_id #{payload_struct.invoiceId}. Possible missed InvoiceCreated event. Creating a new one.")
            # If no record exists, we might need to create one with available data.
            # This logic mirrors parts of InvoiceCreated but marks it as settled.
            received_at_utc = DateTime.utc_now() |> DateTime.truncate(:second)
            metadata = payload_struct.metadata || %{}
            order_id = Map.get(metadata, "orderId") || Map.get(metadata, :orderId)
            fiat_amount_str = get_in(decoded_json_map, ["metadata", "receiptData", "Total"]) ||
                              get_in(decoded_json_map, ["metadata", "posData", "total"])
            parsed_fiat = ParsingUtils.parse_fiat_string(fiat_amount_str)

            attrs = %{
              btcpay_invoice_id: payload_struct.invoiceId,
              btcpay_order_id: order_id,
              status: "settled",
              amount_fiat: parsed_fiat.amount, # Attempt to get fiat from this payload's metadata
              currency_fiat: parsed_fiat.currency,
              final_settled_at_webhook_timestamp: final_settled_ts,
              created_at_webhook_timestamp: final_settled_ts, # Best guess if created event was missed
              received_at: received_at_utc,
              raw_payload_settled: decoded_json_map, # Store raw JSON string of the current InvoiceSettled event
              # Note: crypto details might be missing if InvoicePaymentSettled was also missed
              # For raw_payload_created, it's tricky. We don't have that payload.
              # Storing the current (InvoiceSettled) raw_body might be misleading.
              # Perhaps null or a specific marker map is better.
              raw_payload_created: %{ "note" => "Original InvoiceCreated event was missed. This record auto-created from InvoiceSettled event.", "original_event_invoice_id" => payload_struct.invoiceId, "original_event_timestamp" => payload_struct.timestamp}
            }
            changeset = Transaction.changeset(%Transaction{}, attrs)
            case Repo.insert(changeset, on_conflict: :nothing, conflict_target: :btcpay_invoice_id) do
              {:ok, transaction} ->
                Logger.info("InvoiceSettled: Created and settled transaction #{transaction.id} for invoice #{payload_struct.invoiceId} (as prior events were missed)")
                broadcast_new_transaction_event(transaction)
                {:ok, :created_and_settled, transaction}
              {:error, _changeset_error} -> # Handle duplicate on this fallback creation too
                 Logger.info("InvoiceSettled: Duplicate btcpay_invoice_id #{payload_struct.invoiceId} during fallback creation. Assuming already handled.")
                 # Try to fetch and update just in case it exists from a very late InvoiceCreated
                 if existing_tx = Repo.get_by(Transaction, btcpay_invoice_id: payload_struct.invoiceId) do
                   update_attrs = %{status: "settled", final_settled_at_webhook_timestamp: final_settled_ts, raw_payload_settled: decoded_json_map}
                   cs = Transaction.update_changeset(existing_tx, update_attrs)
                   Repo.update(cs)
                   Logger.info("InvoiceSettled: Updated existing transaction #{existing_tx.id} as settled.")
                   broadcast_updated_transaction_event(existing_tx)
                   {:ok, :updated, existing_tx}
                 else
                   Logger.error("InvoiceSettled: Failed to create or find transaction for #{payload_struct.invoiceId} during fallback.")
                  {:error, :database_error_on_fallback_create}
                 end
            end

          transaction ->
            # If fiat details were missing, try to get them from this payload's metadata
            current_fiat_amount = transaction.amount_fiat
            current_fiat_currency = transaction.currency_fiat

            # Base attributes for the update
            base_update_attrs = %{
              status: "settled",
              final_settled_at_webhook_timestamp: final_settled_ts,
              raw_payload_settled: decoded_json_map # Store raw JSON string
            }

            # Conditionally add fiat details to the update_attrs map
            update_attrs_with_fiat = 
              if is_nil(current_fiat_amount) || is_nil(current_fiat_currency) do
                fiat_amount_str = get_in(decoded_json_map, ["metadata", "receiptData", "Total"]) ||
                                  get_in(decoded_json_map, ["metadata", "posData", "total"])
                parsed_fiat = ParsingUtils.parse_fiat_string(fiat_amount_str)
                
                if parsed_fiat.amount && parsed_fiat.currency do
                  Map.merge(base_update_attrs, %{amount_fiat: parsed_fiat.amount, currency_fiat: parsed_fiat.currency})
                else
                  base_update_attrs # No new fiat info, use base_update_attrs
                end
              else
                base_update_attrs # Fiat info already exists, use base_update_attrs
              end

            changeset = Transaction.update_changeset(transaction, update_attrs_with_fiat)
            case Repo.update(changeset) do
              {:ok, updated_transaction} ->
                Logger.info("InvoiceSettled: Successfully marked transaction #{updated_transaction.id} as settled for invoice #{payload_struct.invoiceId}")
                broadcast_updated_transaction_event(updated_transaction)
                {:ok, :settled, updated_transaction}
              {:error, changeset_error} ->
                Logger.error("InvoiceSettled: Failed to mark transaction as settled for invoice #{payload_struct.invoiceId}. Changeset: #{inspect(changeset_error)}")
                {:error, :database_error, changeset_error}
            end
        end
      else
        {:error, reason} ->
          Logger.error("InvoiceSettled: Failed to parse payload. Reason: #{inspect(reason)}. Data: #{inspect(decoded_json_map)}")
          {:error, :parsing_failed, reason}
      end
    rescue
      e ->
        Logger.error("InvoiceSettled: Unexpected error for payload #{inspect(decoded_json_map)}. Error: #{inspect(e)}, Stacktrace: #{inspect(__STACKTRACE__)}")
        {:error, :unexpected_error, e}
    end
  end

  defp broadcast_new_transaction_event(transaction) do
    Logger.info("Broadcasting :new_transaction_event for #{transaction.id}")
    Endpoint.broadcast("transactions", "new_transaction_event", %{id: transaction.id})
  end

  defp broadcast_updated_transaction_event(transaction) do
    Logger.info("Broadcasting :updated_transaction_event for #{transaction.id}")
    Endpoint.broadcast("transactions", "updated_transaction_event", %{id: transaction.id})
  end

end