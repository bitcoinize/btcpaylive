defmodule BtcpayTracker.ParsingUtils do
  require Logger
  alias Decimal

  def parse_fiat_string(nil), do: %{amount: nil, currency: nil}
  def parse_fiat_string(value) when is_number(value) do
    %{amount: cast_to_decimal(value), currency: nil} # Assuming USD or default if only number
  end
  def parse_fiat_string(fiat_string) when is_binary(fiat_string) do
    # Improved regex to handle various currency symbols and formats
    cond do
      # Format: $123.45, €123.45, £123,45 (currency symbol first, then amount)
      Regex.match?(~r/^(\p{Sc}|[A-Z]{3})\s?([\d,\.]+)/u, fiat_string) ->
        captures = Regex.run(~r/^(\p{Sc}|[A-Z]{3})\s?([\d,\.]+)/u, fiat_string, capture: :all_but_first)
        currency = List.first(captures) |> String.trim()
        amount_str = List.last(captures) |> String.replace(",", ".")
        %{amount: cast_to_decimal(amount_str), currency: currency}

      # Format: 123.45 USD, 123,45 EUR (amount first, then currency code/symbol)
      Regex.match?(~r/^([\d,\.]+)\s?(\p{Sc}|[A-Z]{3})/u, fiat_string) ->
        captures = Regex.run(~r/^([\d,\.]+)\s?(\p{Sc}|[A-Z]{3})/u, fiat_string, capture: :all_but_first)
        amount_str = List.first(captures) |> String.replace(",", ".")
        currency = List.last(captures) |> String.trim()
        %{amount: cast_to_decimal(amount_str), currency: currency}
        
      # Format: 123.45 (just a number, assume default currency or to be filled later)
      Regex.match?(~r/^[\d,\.]+$/, fiat_string) ->
         %{amount: cast_to_decimal(String.replace(fiat_string, ",", ".")), currency: nil}

      true ->
        Logger.warning("Could not parse fiat string: #{fiat_string}")
        %{amount: nil, currency: nil}
    end
  end

  def cast_to_decimal(nil), do: nil
  def cast_to_decimal(value) when is_binary(value) do
    try do
      case Decimal.new(value) do
        {:ok, decimal} -> decimal
        %Decimal{} = decimal -> decimal
        other -> 
          Logger.warning("Could not convert amount string '#{value}' to Decimal. Received: #{inspect(other)}")
          nil
      end
    rescue
      e -> 
        Logger.warning("Error casting binary '#{value}' to Decimal: #{inspect(e)}")
        nil
    end
  end
  def cast_to_decimal(value) when is_number(value) do
    # Convert float to string to ensure Decimal.new/1 compatibility
    value
    |> to_string()
    |> Decimal.new()
  end

  def extract_crypto_currency(nil), do: nil
  def extract_crypto_currency(payment_method_string) when is_binary(payment_method_string) do
    # Example: "BTC-LightningNetwork" -> "BTC", "BTC" -> "BTC"
    String.split(payment_method_string, "-") |> List.first()
  end
end 