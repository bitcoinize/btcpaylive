defmodule BtcpayTracker.IngestionTest do
  use BtcpayTracker.DataCase, async: true
  alias BtcpayTracker.ParsingUtils
  alias Decimal

  describe "parse_fiat_string/1" do
    test "parses fiat string with currency symbol prefix" do
      assert ParsingUtils.parse_fiat_string("$123.45") == %{amount: Decimal.new("123.45"), currency: "$"}
      assert ParsingUtils.parse_fiat_string("€123.45") == %{amount: Decimal.new("123.45"), currency: "€"}
      assert ParsingUtils.parse_fiat_string("£123,45") == %{amount: Decimal.new("123.45"), currency: "£"}
    end

    test "parses fiat string with currency code suffix" do
      assert ParsingUtils.parse_fiat_string("123.45 USD") == %{amount: Decimal.new("123.45"), currency: "USD"}
      assert ParsingUtils.parse_fiat_string("123,45 EUR") == %{amount: Decimal.new("123.45"), currency: "EUR"}
    end

    test "parses fiat string with only numbers" do
      assert ParsingUtils.parse_fiat_string("123.45") == %{amount: Decimal.new("123.45"), currency: nil}
      assert ParsingUtils.parse_fiat_string("123,45") == %{amount: Decimal.new("123.45"), currency: nil}
    end

    test "handles nil and unparseable strings" do
      assert ParsingUtils.parse_fiat_string(nil) == %{amount: nil, currency: nil}
      assert ParsingUtils.parse_fiat_string("invalid") == %{amount: nil, currency: nil}
      assert ParsingUtils.parse_fiat_string("USD") == %{amount: nil, currency: nil} # Only currency, no amount
    end
    
    test "parses fiat string with currency symbol suffix" do
      assert ParsingUtils.parse_fiat_string("123.45$") == %{amount: Decimal.new("123.45"), currency: "$"}
    end

    test "parses fiat string with space between symbol and amount" do
      assert ParsingUtils.parse_fiat_string("$ 123.45") == %{amount: Decimal.new("123.45"), currency: "$"}
      assert ParsingUtils.parse_fiat_string("123.45 EUR") == %{amount: Decimal.new("123.45"), currency: "EUR"}
    end
  end

  describe "cast_to_decimal/1" do
    test "casts valid binary to decimal" do
      assert Decimal.equal?(ParsingUtils.cast_to_decimal("123.45"), Decimal.new("123.45"))
      assert Decimal.equal?(ParsingUtils.cast_to_decimal("0.00000001"), Decimal.new("0.00000001"))
    end

    test "casts valid number to decimal" do
      assert Decimal.equal?(ParsingUtils.cast_to_decimal(123.45), Decimal.new("123.45"))
      assert Decimal.equal?(ParsingUtils.cast_to_decimal(123), Decimal.new(123))
    end

    test "handles nil for cast_to_decimal" do
      assert ParsingUtils.cast_to_decimal(nil) == nil
    end

    test "handles invalid binary for cast_to_decimal" do
      assert ParsingUtils.cast_to_decimal("invalid") == nil
      assert ParsingUtils.cast_to_decimal("1.2.3") == nil
    end
  end

  describe "extract_crypto_currency/1" do
    test "extracts currency from payment method string" do
      assert ParsingUtils.extract_crypto_currency("BTC-LightningNetwork") == "BTC"
      assert ParsingUtils.extract_crypto_currency("BTC") == "BTC"
      assert ParsingUtils.extract_crypto_currency("LTC-OnChain") == "LTC"
    end

    test "handles nil for extract_crypto_currency" do
      assert ParsingUtils.extract_crypto_currency(nil) == nil
    end

    test "handles empty string for extract_crypto_currency" do
      assert ParsingUtils.extract_crypto_currency("") == "" 
    end
  end
end 