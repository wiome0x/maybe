class DataTrackingController < ApplicationController
  SECURITY_ALIASES = {
    "AAPL" => { en: "Apple", zh: "苹果", quick: true },
    "MSFT" => { en: "Microsoft", zh: "微软", quick: true },
    "GOOGL" => { en: "Alphabet", zh: "谷歌", quick: true },
    "AMZN" => { en: "Amazon", zh: "亚马逊", quick: true },
    "NVDA" => { en: "NVIDIA", zh: "英伟达", quick: true },
    "META" => { en: "Meta", zh: "Meta", quick: true },
    "TSLA" => { en: "Tesla", zh: "特斯拉", quick: true }
  }.freeze

  def index
    @breadcrumbs = [ [ t("layouts.application.home"), root_path ], [ t("layouts.application.data_tracking"), nil ] ]
    load_trend_data
  end

  def trend
    load_trend_data
  end

  private
    def load_trend_data
      scoped_prices = Current.family.historical_prices
      available_tickers = scoped_prices.distinct.order(:ticker).pluck(:ticker)

      @default_ticker = if available_tickers.include?("AAPL")
        "AAPL"
      else
        available_tickers.first
      end
      @selected_ticker = params[:ticker].presence&.upcase || @default_ticker

      date_scope = @selected_ticker.present? ? scoped_prices.by_ticker(@selected_ticker) : scoped_prices
      @default_start_date = [ date_scope.minimum(:date), 3.years.ago.to_date ].compact.max
      @default_end_date = date_scope.maximum(:date) || Date.current
      @start_date = params[:start_date].presence || @default_start_date&.iso8601
      @end_date = params[:end_date].presence || @default_end_date&.iso8601

      @prices = if @selected_ticker.present?
        scoped_prices
          .by_ticker(@selected_ticker)
          .by_date_range(@start_date, @end_date)
          .ordered_by_date
          .select(:date, :close)
      else
        HistoricalPrice.none
      end

      @ticker_options = available_tickers.map do |ticker|
        aliases = SECURITY_ALIASES.fetch(ticker, {})
        {
          ticker: ticker,
          en_name: aliases[:en],
          zh_name: aliases[:zh],
          quick: aliases[:quick] || false
        }
      end
      @quick_ticker_options = SECURITY_ALIASES.map do |ticker, aliases|
        {
          ticker: ticker,
          en_name: aliases[:en],
          zh_name: aliases[:zh],
          quick: true,
          available: available_tickers.include?(ticker)
        }
      end
    end
end
