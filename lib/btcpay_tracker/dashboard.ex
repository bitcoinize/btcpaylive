defmodule BtcpayTracker.Dashboard do
  @moduledoc """
  Context module for dashboard-related queries.
  """
  import Ecto.Query, warn: false
  alias BtcpayTracker.Transactions.Transaction

  @doc """
  Counts the total number of settled transactions.
  For now, counts all transactions. Later can be refined for 'settled' status.
  """
  def count_total_transactions(repo \\ BtcpayTracker.Repo) do
    from(t in Transaction, select: count(t.id)) # Counting all for now, will refine by status
    |> repo.one() || 0
  end

  @doc """
  Calculates the sum of `amount_fiat` for all transactions, grouped by `currency_fiat`.
  Assumes 'settled' transactions. For now, sums all. TODO: Filter by status = 'settled'
  """
  def sum_total_value_fiat(repo \\ BtcpayTracker.Repo) do
    query = from t in Transaction,
            where: t.status == "settled" and not is_nil(t.amount_fiat) and not is_nil(t.currency_fiat),
            group_by: t.currency_fiat,
            select: {t.currency_fiat, sum(t.amount_fiat)}

    repo.all(query)
    |> Enum.into(%{}, fn {currency, total} -> {currency, total || Decimal.new(0)} end)
  end

  @doc """
  Calculates the average `amount_fiat` for all transactions, grouped by `currency_fiat`.
  Assumes 'settled' transactions. For now, averages all. TODO: Filter by status = 'settled'
  """
  def avg_transaction_value_fiat(repo \\ BtcpayTracker.Repo) do
    query = from t in Transaction,
            where: t.status == "settled" and not is_nil(t.amount_fiat) and not is_nil(t.currency_fiat),
            group_by: t.currency_fiat,
            select: {t.currency_fiat, avg(t.amount_fiat)}

    repo.all(query)
    |> Enum.into(%{}, fn {currency, avg_val} -> {currency, avg_val || Decimal.new(0)} end)
  end

  @doc """
  Gets the count of transactions for each `payment_method`.
  Assumes 'settled' transactions. For now, groups all. TODO: Filter by status = 'settled'
  """
  def get_payment_method_breakdown(repo \\ BtcpayTracker.Repo) do
    query = from t in Transaction,
            where: t.status == "settled",
            group_by: t.payment_method,
            select: {t.payment_method, count(t.id)}

    repo.all(query)
    |> Enum.into(%{}, fn {method, count} -> {method || "N/A", count} end)
  end

  @doc """
  Lists recent transactions, ordered by `inserted_at` descending.
  """
  def list_recent_transactions(limit \\ 10, repo \\ BtcpayTracker.Repo) do
    from(t in Transaction,
      order_by: [desc: t.inserted_at],
      limit: ^limit)
    |> repo.all()
  end

  @doc """
  Calculates the sum of `amount_crypto` for all transactions, grouped by `currency_crypto`.
  TODO: Filter by status = 'settled'
  """
  def sum_total_value_crypto(repo \\ BtcpayTracker.Repo) do
    query = from t in Transaction,
            where: t.status == "settled" and not is_nil(t.amount_crypto) and not is_nil(t.currency_crypto),
            group_by: t.currency_crypto,
            select: {t.currency_crypto, sum(t.amount_crypto)}

    repo.all(query)
    |> Enum.into(%{}, fn {currency, total} -> {currency, total || Decimal.new(0)} end)
  end

  @doc """
  Calculates the average `amount_crypto` for all transactions, grouped by `currency_crypto`.
  TODO: Filter by status = 'settled'
  """
  def avg_transaction_value_crypto(repo \\ BtcpayTracker.Repo) do
    query = from t in Transaction,
            where: t.status == "settled" and not is_nil(t.amount_crypto) and not is_nil(t.currency_crypto),
            group_by: t.currency_crypto,
            select: {t.currency_crypto, avg(t.amount_crypto)}

    repo.all(query)
    |> Enum.into(%{}, fn {currency, avg_val} -> {currency, avg_val || Decimal.new(0)} end)
  end

  @doc """
  Counts the number of distinct (non-null) store_ids.
  """
  def count_distinct_store_ids(repo \\ BtcpayTracker.Repo) do
    query = from t in Transaction,
            where: not is_nil(t.store_id),
            select: count(t.store_id, :distinct)
    
    repo.one(query) || 0
  end
end 