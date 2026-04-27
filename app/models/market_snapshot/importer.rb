class MarketSnapshot::Importer
  JOB_NAME = "import_market_snapshots".freeze

  def initialize(date: Date.current, provider: nil)
    @date     = date
    @provider = provider || resolve_provider
  end

  def import
    run = ScheduledJobRun.create!(
      job_name: JOB_NAME,
      run_date: @date,
      status: "running",
      started_at: Time.current
    )

    symbols = collect_symbols

    raise "No provider available for market snapshots" unless @provider

    response = @provider.fetch_market_data(symbols)
    raise "Provider error: #{response.error&.message}" unless response.success?

    count = upsert_snapshots(response.data)

    run.update!(
      status: "completed",
      finished_at: Time.current,
      records_written: count,
      symbols_requested: symbols.size,
      symbols_succeeded: response.data.size,
      source: @provider.class.name.demodulize.underscore
    )
  rescue => e
    run&.update!(status: "failed", finished_at: Time.current, error_message: e.message)
    Rails.logger.error("MarketSnapshot::Importer failed on #{@date}: #{e.message}")
  end

  private

    def collect_symbols
      watchlist_symbols = WatchlistItem.stocks.distinct.pluck(:symbol)
      default_symbols   = WatchlistItem::DEFAULT_STOCKS.pluck(:symbol)
      (default_symbols + watchlist_symbols).uniq
    end

    def upsert_snapshots(quotes)
      return 0 if quotes.empty?

      rows = quotes.map do |q|
        {
          symbol:         q.symbol,
          name:           q.name,
          date:           @date,
          item_type:      q.item_type.presence || "stock",
          price:          q.price,
          open_price:     q.open_price,
          prev_close:     q.prev_close,
          high:           q.high,
          low:            q.low,
          change_percent: q.change_percent,
          volume:         q.volume,
          market_cap:     q.market_cap,
          currency:       "USD",
          source:         @provider.class.name.demodulize.underscore,
          created_at:     Time.current,
          updated_at:     Time.current
        }
      end

      MarketSnapshot.upsert_all(rows, unique_by: [ :symbol, :date ])
      rows.size
    end

    def resolve_provider
      Provider::Registry.get_provider(:finnhub) ||
        Provider::Registry.get_provider(:yahoo_finance)
    rescue Provider::Registry::Error
      nil
    end
end
