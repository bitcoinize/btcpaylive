defmodule BtcpayTrackerWeb.DashboardLive do
  use BtcpayTrackerWeb, :live_view

  alias BtcpayTracker.Dashboard.MetricsAggregator

  @metrics_updated_topic "dashboard_summary_update"

  @impl true
  def mount(_params, _session, socket) do
    # Fetch initial data from the MetricsAggregator (which reads from ETS)
    metrics = MetricsAggregator.get_metrics()
    socket = assign_metrics_to_socket(socket, metrics)

    if connected?(socket) do
      # Subscribe to summary updates from MetricsAggregator
      Phoenix.PubSub.subscribe(BtcpayTracker.PubSub, @metrics_updated_topic)
    end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <h1 class="text-3xl font-bold mb-6 text-center">Real-time Transaction Dashboard</h1>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-8">
        <div class="bg-white shadow-lg rounded-lg p-4">
          <h2 class="text-lg font-semibold text-gray-700 mb-1">Total Transactions</h2>
          <p class="text-3xl font-bold text-blue-600"><%= @total_transactions %></p>
        </div>

        <div class="bg-white shadow-lg rounded-lg p-4">
          <h2 class="text-lg font-semibold text-gray-700 mb-1">Participating Stores</h2>
          <p class="text-3xl font-bold text-teal-500"><%= @distinct_store_count %></p>
        </div>

        <div class="bg-white shadow-lg rounded-lg p-4">
          <h2 class="text-lg font-semibold text-gray-700 mb-1">Total Value (<%= @primary_fiat_currency %>)</h2>
          <p class="text-3xl font-bold text-green-600"><%= @primary_fiat_currency_symbol %><%= format_decimal(@total_value_primary_fiat, 2) %></p>
        </div>

        <div class="bg-white shadow-lg rounded-lg p-4">
          <h2 class="text-lg font-semibold text-gray-700 mb-1">Avg Tx (<%= @primary_fiat_currency %>)</h2>
          <p class="text-3xl font-bold text-purple-600"><%= @primary_fiat_currency_symbol %><%= format_decimal(@average_transaction_primary_fiat, 2) %></p>
        </div>

        <div class="bg-white shadow-lg rounded-lg p-4">
          <h2 class="text-lg font-semibold text-gray-700 mb-1">Total Value (BTC)</h2>
          <p class="text-3xl font-bold text-orange-500"><%= format_decimal(@total_value_btc, 8) %> BTC</p>
        </div>

        <div class="bg-white shadow-lg rounded-lg p-4">
          <h2 class="text-lg font-semibold text-gray-700 mb-1">Avg Tx (BTC)</h2>
          <p class="text-3xl font-bold text-yellow-500"><%= format_decimal(@average_transaction_btc, 8) %> BTC</p>
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-1 lg:grid-cols-1 gap-6 mb-8">
        <div class="bg-white shadow-lg rounded-lg p-6">
          <h2 class="text-xl font-semibold text-gray-700 mb-2">Payment Methods Breakdown</h2>
          <%= if Enum.empty?(@payment_method_breakdown) do %>
            <p class="text-gray-500">No data yet.</p>
          <% else %>
            <ul class="space-y-1">
              <%= for {method, count} <- @payment_method_breakdown do %>
                <li class="flex justify-between text-sm">
                  <span class="text-gray-600"><%= method || "N/A" %>:</span>
                  <span class="font-semibold"><%= count %></span>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>
      </div>

      <div class="bg-white shadow-lg rounded-lg p-6">
        <h2 class="text-2xl font-semibold text-gray-700 mb-4">Recent Transactions (<%= Enum.count(@recent_transactions) %>)</h2>
        <%= if Enum.empty?(@recent_transactions) do %>
          <p class="text-gray-500">No transactions recorded yet.</p>
        <% else %>
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Invoice ID</th>
                  <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
                  <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Fiat Amount</th>
                  <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Crypto Amount</th>
                  <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Payment Method</th>
                  <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Received At</th>
                  <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Order Link</th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for tx <- @recent_transactions do %>
                  <tr>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 font-mono text-xs"><%= tx.btcpay_invoice_id %></td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                        <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full " <> status_color_class(tx.status)}>
                            <%= tx.status %>
                        </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500"><%= tx.currency_fiat %> <%= tx.amount_fiat || "0.00" %></td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500"><%= tx.currency_crypto || "N/A" %> <%= tx.amount_crypto || "N/A" %></td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500"><%= tx.payment_method || "N/A" %></td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <%= if tx.received_at do %>
                        <%= Timex.format!(tx.received_at, "{YYYY}-{0M}-{0D} {h24}:{m}:{s}") %>
                      <% else %>
                        N/A
                      <% end %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <%=
                        # Use get_in to safely access nested :metadata -> "orderUrl"
                        order_url = get_in(tx.raw_payload_created, ["metadata", "orderUrl"])
                        if order_url do
                      %>
                        <a href={order_url} target="_blank" class="text-indigo-600 hover:text-indigo-900 font-medium py-1 px-3 rounded-md bg-indigo-100 hover:bg-indigo-200 transition-colors duration-150 ease-in-out">
                          View Order
                        </a>
                      <% else %>
                        N/A
                      <% end %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Handle summary updates from MetricsAggregator
  @impl true
  def handle_info({:metrics_updated, new_metrics}, socket) do
    IO.puts("DashboardLive: Received :metrics_updated via PubSub")
    socket = assign_metrics_to_socket(socket, new_metrics)
    {:noreply, socket}
  end

  # Helper to assign metrics from the map provided by MetricsAggregator
  defp assign_metrics_to_socket(socket, metrics) do
    primary_currency_code = Application.get_env(:btcpay_tracker, :primary_fiat_currency, "USD")
    primary_currency_symbol = currency_symbol(primary_currency_code)

    # Extract fiat values, providing defaults
    total_value_fiat_map = Map.get(metrics, :total_value_fiat, %{})
    avg_transaction_fiat_map = Map.get(metrics, :avg_transaction_value_fiat, %{})

    total_value_primary_fiat =
      total_value_fiat_map[primary_currency_code] ||
      total_value_fiat_map["USD"] || # Fallback for common case
      Map.values(total_value_fiat_map) |> List.first() || Decimal.new(0)

    average_transaction_primary_fiat =
      avg_transaction_fiat_map[primary_currency_code] ||
      avg_transaction_fiat_map["USD"] || # Fallback
      Map.values(avg_transaction_fiat_map) |> List.first() || Decimal.new(0)

    # Extract crypto values, providing defaults
    total_value_crypto_map = Map.get(metrics, :total_value_crypto, %{})
    avg_transaction_crypto_map = Map.get(metrics, :avg_transaction_value_crypto, %{})

    total_value_btc = total_value_crypto_map["BTC"] || Decimal.new(0)
    average_transaction_btc = avg_transaction_crypto_map["BTC"] || Decimal.new(0)

    socket
    |> assign(
      total_transactions: Map.get(metrics, :total_transactions, 0),
      distinct_store_count: Map.get(metrics, :participating_stores, 0),
      primary_fiat_currency: primary_currency_code,
      primary_fiat_currency_symbol: primary_currency_symbol,
      total_value_primary_fiat: total_value_primary_fiat,
      average_transaction_primary_fiat: average_transaction_primary_fiat,
      total_value_btc: total_value_btc,
      average_transaction_btc: average_transaction_btc,
      payment_method_breakdown: Map.get(metrics, :payment_method_breakdown, []),
      recent_transactions: Map.get(metrics, :recent_transactions, [])
    )
  end

  defp currency_symbol("USD"), do: "$"
  defp currency_symbol("EUR"), do: "€"
  defp currency_symbol("GBP"), do: "£"
  defp currency_symbol(_other), do: ""

  defp status_color_class("settled"), do: "bg-green-100 text-green-800"
  defp status_color_class("pending"), do: "bg-yellow-100 text-yellow-800"
  defp status_color_class("processing_payment"), do: "bg-blue-100 text-blue-800"
  defp status_color_class(_), do: "bg-gray-100 text-gray-800"

  # Helper to format decimals for display, avoiding float conversion issues for currency
  defp format_decimal(nil, precision) do
    # For nil, return a string with the correct number of decimal places for consistency
    String.duplicate("0", 1) <> "." <> String.duplicate("0", precision)
  end
  
  defp format_decimal(decimal_val, precision) when is_struct(decimal_val, Decimal) do
    # For Decimal 2.0.0, first round, then convert to string using :normal type.
    decimal_val
    |> Decimal.round(precision)
    |> Decimal.to_string(:normal) 
  end
  
  defp format_decimal(other_val, precision) do
    try do
      val_to_convert =
        cond do
          is_float(other_val) -> Decimal.from_float(other_val)
          is_integer(other_val) -> Decimal.new(other_val)
          is_binary(other_val) -> Decimal.new(other_val)
          true -> raise "Cannot convert to Decimal"
        end
  
      val_to_convert
      |> Decimal.round(precision)
      |> Decimal.to_string(:normal)
    rescue
      _ -> # If conversion to Decimal fails
        default_whole = "0"
        default_frac = String.duplicate("0", precision)
        # Consider logging this occurrence if it's unexpected
        # Logger.warn("format_decimal received non-Decimal, non-convertible value: #{inspect(other_val)}")
        default_whole <> "." <> default_frac
    end
  end
end 