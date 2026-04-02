class Settings::DatabasesController < ApplicationController
  layout "settings"

  before_action :require_admin

  def show
    @tables = ActiveRecord::Base.connection.tables.sort.map do |table_name|
      count = ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM #{ActiveRecord::Base.connection.quote_table_name(table_name)}").first["count"]
      { name: table_name, count: count }
    end
  end

  def table
    table_name = params[:table]
    unless ActiveRecord::Base.connection.tables.include?(table_name)
      redirect_to settings_database_path, alert: "Table not found."
      return
    end

    @table_name = table_name
    @columns = ActiveRecord::Base.connection.columns(table_name)
    page = (params[:page] || 1).to_i
    per_page = 25
    offset = (page - 1) * per_page

    quoted = ActiveRecord::Base.connection.quote_table_name(table_name)
    @total = ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM #{quoted}").first["count"]
    @rows = ActiveRecord::Base.connection.exec_query(
      "SELECT * FROM #{quoted} ORDER BY 1 DESC LIMIT $1 OFFSET $2",
      "SQL",
      [ per_page, offset ]
    ).to_a
    @page = page
    @total_pages = (@total.to_f / per_page).ceil
  end

  def export_table
    table_name = params[:table]
    unless ActiveRecord::Base.connection.tables.include?(table_name)
      redirect_to settings_database_path, alert: "Table not found."
      return
    end

    quoted = ActiveRecord::Base.connection.quote_table_name(table_name)
    columns = ActiveRecord::Base.connection.columns(table_name).map(&:name)
    rows = ActiveRecord::Base.connection.execute("SELECT * FROM #{quoted} ORDER BY 1").to_a

    csv_data = CSV.generate do |csv|
      csv << columns
      rows.each { |row| csv << columns.map { |c| row[c] } }
    end

    send_data csv_data,
      filename: "#{table_name}_#{Date.current.strftime('%Y%m%d')}.csv",
      type: "text/csv",
      disposition: "attachment"
  end

  private
    def require_admin
      unless Current.user.admin?
        redirect_to root_path, alert: "Not authorized."
      end
    end
end
