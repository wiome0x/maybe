class DataTrackingController < ApplicationController
  def index
    @imports = Current.family.imports.where(type: "HistoricalDataImport").ordered
    @breadcrumbs = [ [ "Home", root_path ], [ "Data Tracking", nil ] ]
  end

  def trend
    if params[:ticker].present?
      @prices = Current.family.historical_prices
                      .by_ticker(params[:ticker])
                      .by_date_range(params[:start_date], params[:end_date])
                      .ordered_by_date
                      .select(:date, :close)
    else
      @prices = HistoricalPrice.none
    end
  end
end
