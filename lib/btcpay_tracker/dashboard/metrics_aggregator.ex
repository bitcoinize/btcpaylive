defmodule BtcpayTracker.Dashboard.MetricsAggregator do
  use GenServer
  require Logger

  alias BtcpayTracker.Dashboard
  # alias BtcpayTracker.PubSub # Removed unused alias

  @ets_table :dashboard_metrics_cache
  @refresh_interval_ms 2_000 # 2 seconds
  @metrics_updated_topic "dashboard_summary_update"

  # Client API
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def get_metrics do
    case :ets.lookup(@ets_table, :all_metrics) do
      [{:all_metrics, metrics}] -> metrics
      [] -> %{} # Return empty map if not yet populated
    end
  end

  # GenServer Callbacks
  @impl true
  def init(_opts) do
    Logger.info("Starting Dashboard.MetricsAggregator...")
    :ets.new(@ets_table, [:set, :public, :named_table, read_concurrency: true])
    Phoenix.PubSub.subscribe(BtcpayTracker.PubSub, "transactions")
    
    if Mix.env() != :test do
      load_and_cache_metrics()
    end
    
    schedule_refresh() # Can still schedule, it will just load into an empty ETS first time in test
    {:ok, %{}}
  end

  @impl true
  def handle_info({:new_transaction_event, _payload}, state) do
    # For immediate (but potentially overwhelming) refresh:
    # load_and_cache_metrics()
    # For now, rely on the periodic refresh to pick up changes.
    # A more advanced version could debounce this.
    Logger.debug("MetricsAggregator: Received :new_transaction_event")
    {:noreply, state}
  end

  @impl true
  def handle_info({:updated_transaction_event, _payload}, state) do
    Logger.debug("MetricsAggregator: Received :updated_transaction_event")
    # Similar to :new_transaction_event, rely on periodic refresh for now.
    {:noreply, state}
  end

  @impl true
  def handle_info(:refresh_metrics, state) do
    Logger.debug("MetricsAggregator: Refreshing metrics from DB and updating ETS")
    load_and_cache_metrics()
    schedule_refresh()
    {:noreply, state}
  end

  defp load_and_cache_metrics do
    # current_env = Mix.env()
    # Logger.error("%%%%%%%%%% METRICS AGGREGATOR: Mix.env IS: #{inspect(current_env)} %%%%%%%%%%") # REMOVED LOUD LOG

    if Mix.env() == :test do # This check should now work
      Logger.debug("MetricsAggregator: Skipping metrics load in test environment during this call.")
      # Optionally, insert empty/default metrics into ETS for tests if needed immediately
      # :ets.insert(@ets_table, {:all_metrics, default_test_metrics()})
      # Phoenix.PubSub.broadcast(BtcpayTracker.PubSub, @metrics_updated_topic, {:metrics_updated, default_test_metrics()})
      :ok
    else
      Logger.debug("MetricsAggregator: Loading metrics from BtcpayTracker.Dashboard using Repo.Replica")
      # These calls will go to the database (ideally the read replica in the future)
      replica_repo = BtcpayTracker.Repo.Replica # Define the replica repo module

      all_metrics = %{
        total_transactions: Dashboard.count_total_transactions(replica_repo),
        total_value_fiat: Dashboard.sum_total_value_fiat(replica_repo), # This returns a map like %{"USD" => sum}
        avg_transaction_value_fiat: Dashboard.avg_transaction_value_fiat(replica_repo), # This returns a map
        payment_method_breakdown: Dashboard.get_payment_method_breakdown(replica_repo),
        recent_transactions: Dashboard.list_recent_transactions(10, replica_repo), # Assuming default limit 10, explicitly pass repo
        total_value_crypto: Dashboard.sum_total_value_crypto(replica_repo), # This returns a map
        avg_transaction_value_crypto: Dashboard.avg_transaction_value_crypto(replica_repo), # This returns a map
        participating_stores: Dashboard.count_distinct_store_ids(replica_repo)
      }

      :ets.insert(@ets_table, {:all_metrics, all_metrics})
      Logger.debug("MetricsAggregator: Metrics updated in ETS. Broadcasting summary.")
      Phoenix.PubSub.broadcast(BtcpayTracker.PubSub, @metrics_updated_topic, {:metrics_updated, all_metrics})
    end
  rescue
    e ->
      Logger.error("MetricsAggregator: Error loading/caching metrics: #{inspect(e)}")
      # Decide if to retry or just wait for next scheduled refresh
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh_metrics, @refresh_interval_ms)
  end
end 