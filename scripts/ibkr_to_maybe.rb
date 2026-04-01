#!/usr/bin/env ruby
# frozen_string_literal: true

# IBKR Activity Statement to Maybe CSV Converter
#
# Usage:
#   ruby scripts/ibkr_to_maybe.rb <ibkr_activity_statement.csv>
#
# Outputs:
#   - <filename>_trades.csv   (for TradeImport in Maybe)
#   - <filename>_transactions.csv (for TransactionImport: dividends, fees, deposits, etc.)

require "csv"

class IbkrToMaybe
  EXCHANGE_MIC_MAP = {
    "NASDAQ" => "XNAS",
    "NYSE" => "XNYS",
    "ARCA" => "ARCX",
    "AMEX" => "XASE",
    "BATS" => "BATS",
    "IEX" => "IEXG",
    "LSE" => "XLON",
    "TSE" => "XTSE",
    "HKEX" => "XHKG",
    "SGX" => "XSES"
  }.freeze

  def initialize(filepath)
    @filepath = filepath
    @basename = File.basename(filepath, File.extname(filepath))
    @dir = File.dirname(filepath)
    @trades = []
    @transactions = []
  end

  def convert
    parse_sections
    write_trades_csv
    write_transactions_csv
    print_summary
  end

  private

    def parse_sections
      lines = File.readlines(@filepath, encoding: "UTF-8")

      lines.each do |line|
        row = CSV.parse_line(line)
        next if row.nil? || row.empty?

        section = row[0]&.strip
        discriminator = row[1]&.strip

        case section
        when "交易"
          parse_trade_row(row) if discriminator == "Data"
        when "股息"
          parse_dividend_row(row) if discriminator == "Data"
        when "代扣税"
          parse_withholding_row(row) if discriminator == "Data"
        when "存款和取款"
          parse_deposit_row(row) if discriminator == "Data"
        end
      end
    end

    def parse_trade_row(row)
      # Trade rows have DataDiscriminator at index 2
      data_type = row[2]&.strip
      return unless data_type == "Order"

      asset_class = row[3]&.strip
      return unless asset_class == "股票" # Only stock trades, skip forex

      currency = row[4]&.strip
      ticker = row[5]&.strip
      datetime = row[6]&.strip
      qty = row[7]&.to_f
      price = row[8]&.to_f

      return if ticker.nil? || ticker.empty?

      date = datetime&.split(",")&.first&.strip

      @trades << {
        date: date,
        ticker: ticker,
        exchange_operating_mic: lookup_mic(ticker),
        currency: currency,
        qty: qty,
        price: price,
        name: "#{qty > 0 ? 'Buy' : 'Sell'} #{ticker}"
      }
    end

    def parse_dividend_row(row)
      return if row[2]&.strip == "总数"

      currency = row[2]&.strip
      date = row[3]&.strip
      description = row[4]&.strip
      amount = row[5]&.to_f

      @transactions << {
        date: date,
        amount: -amount, # Dividends are inflows (negative in Maybe)
        name: description,
        currency: currency,
        category: "Income",
        notes: "Dividend"
      }
    end

    def parse_withholding_row(row)
      return if row[2]&.strip == "总数"

      currency = row[2]&.strip
      date = row[3]&.strip
      description = row[4]&.strip
      amount = row[5]&.to_f

      @transactions << {
        date: date,
        amount: amount.abs, # Withholding is an outflow (positive in Maybe)
        name: description,
        currency: currency,
        category: "Taxes",
        notes: "Withholding tax"
      }
    end

    def parse_deposit_row(row)
      return if row[2]&.strip&.start_with?("总数")

      currency = row[2]&.strip
      date = row[3]&.strip
      description = row[4]&.strip
      amount = row[5]&.to_f

      @transactions << {
        date: date,
        amount: -amount, # Deposits are inflows (negative in Maybe)
        name: description,
        currency: currency,
        category: "Transfer",
        notes: "IBKR #{amount > 0 ? 'Deposit' : 'Withdrawal'}"
      }
    end

    def lookup_mic(ticker)
      # Use the financial instrument info if available, fallback to XNAS
      @instrument_mics ||= parse_instrument_info
      @instrument_mics[ticker] || "XNAS"
    end

    def parse_instrument_info
      mics = {}
      lines = File.readlines(@filepath, encoding: "UTF-8")

      lines.each do |line|
        row = CSV.parse_line(line)
        next if row.nil? || row.empty?

        section = row[0]&.strip
        discriminator = row[1]&.strip

        if section == "金融产品信息" && discriminator == "Data"
          ticker = row[3]&.strip
          exchange = row[7]&.strip
          mics[ticker] = EXCHANGE_MIC_MAP[exchange] || exchange if ticker && exchange
        end
      end

      mics
    end

    def write_trades_csv
      return if @trades.empty?

      output = File.join(@dir, "#{@basename}_trades.csv")
      CSV.open(output, "w") do |csv|
        csv << %w[date ticker exchange_operating_mic currency qty price name]
        @trades.each do |t|
          csv << [ t[:date], t[:ticker], t[:exchange_operating_mic], t[:currency], t[:qty], t[:price], t[:name] ]
        end
      end
      puts "Trades CSV: #{output} (#{@trades.size} records)"
    end

    def write_transactions_csv
      return if @transactions.empty?

      output = File.join(@dir, "#{@basename}_transactions.csv")
      CSV.open(output, "w") do |csv|
        csv << %w[date amount name currency category notes]
        @transactions.each do |t|
          csv << [ t[:date], t[:amount], t[:name], t[:currency], t[:category], t[:notes] ]
        end
      end
      puts "Transactions CSV: #{output} (#{@transactions.size} records)"
    end

    def print_summary
      puts "\n=== Conversion Summary ==="
      puts "Stock trades: #{@trades.size}"
      puts "Transactions (dividends/deposits/taxes): #{@transactions.size}"
      puts "\nImport into Maybe:"
      puts "  1. Trades CSV    -> New Import -> Trade Import"
      puts "  2. Transactions  -> New Import -> Transaction Import"
    end
end

if ARGV.empty?
  puts "Usage: ruby scripts/ibkr_to_maybe.rb <ibkr_activity_statement.csv>"
  exit 1
end

IbkrToMaybe.new(ARGV[0]).convert
