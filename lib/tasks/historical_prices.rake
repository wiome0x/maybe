# frozen_string_literal: true

namespace :historical_prices do
  desc <<~DESC
    Bulk import historical price data from a large CSV file using PostgreSQL temp table + upsert.

    Expected CSV format (header names are case-insensitive):
      Ticker,Date,Open,High,Low,Close,Adj Close,Volume
      A,2000-01-03,47.07,47.18,40.27,43.04,43.04,4674353

    Usage:
      rake historical_prices:bulk_import[/path/to/file.csv]
      rake historical_prices:bulk_import[/path/to/file.csv,user@example.com]

    Arguments:
      file_path  - Absolute path to the CSV file inside the container (required)
      user_email - Email of the user whose family owns the data (uses first admin if omitted)

    Examples:
      rake historical_prices:bulk_import[/tmp/data/SP500.csv]
      rake "historical_prices:bulk_import[/tmp/data/SP500.csv,admin@example.com]"
  DESC
  task :bulk_import, [ :file_path, :user_email ] => :environment do |_t, args|
    file_path  = args[:file_path]
    user_email = args[:user_email]

    abort "ERROR: file_path is required.\nUsage: rake historical_prices:bulk_import[/path/to/file.csv]" unless file_path.present?
    abort "ERROR: File not found: #{file_path}" unless File.exist?(file_path)

    # Resolve user and family
    user = if user_email.present?
      User.find_by!(email: user_email)
    else
      User.where(role: :admin).first!
    end
    family = user.family

    file_size_mb = (File.size(file_path).to_f / 1024 / 1024).round(2)
    puts "=" * 60
    puts "Historical Price Bulk Import"
    puts "=" * 60
    puts "  File:   #{file_path} (#{file_size_mb} MB)"
    puts "  Family: #{family.id}"
    puts "  User:   #{user.email}"
    puts "=" * 60

    # ── Step 1: Detect CSV structure ──────────────────────────
    puts "\n[1/5] Detecting CSV structure..."
    first_lines = File.foreach(file_path).first(3)
    col_sep = first_lines.first.include?(";") ? ";" : ","
    raw_headers = CSV.parse_line(first_lines.first, col_sep: col_sep).map(&:strip)

    # Build case-insensitive header lookup
    hdr = {}
    raw_headers.each { |h| hdr[h.downcase.gsub(/\s+/, "_")] = h }

    # Validate required columns
    required = %w[ticker date close]
    missing = required.select { |k| hdr[k].nil? }
    abort "ERROR: Missing required columns: #{missing.join(', ')}.\nFound: #{raw_headers.join(', ')}" if missing.any?

    puts "  Separator: '#{col_sep}'"
    puts "  Headers:   #{raw_headers.join(', ')}"
    puts "  Sample:    #{first_lines[1]&.strip}"

    # ── Step 2: Scan unique tickers ───────────────────────────
    puts "\n[2/5] Scanning tickers..."
    ticker_header = hdr["ticker"]
    tickers = Set.new
    CSV.foreach(file_path, headers: true, col_sep: col_sep, liberal_parsing: true) do |row|
      val = row[ticker_header]&.strip&.upcase
      tickers << val if val.present?
    end
    puts "  Found #{tickers.size} unique tickers"

    # ── Step 3: Resolve securities ────────────────────────────
    puts "\n[3/5] Resolving securities..."
    security_map = {} # ticker => uuid
    tickers.each_with_index do |ticker, idx|
      print "\r  #{idx + 1}/#{tickers.size} #{ticker.ljust(10)}"
      begin
        security = Security::Resolver.new(ticker).resolve
        security_map[ticker] = security.id if security
      rescue => e
        puts "\n  WARNING: #{ticker}: #{e.message}"
      end
    end
    puts "\n  Resolved #{security_map.size}/#{tickers.size} securities"

    unresolved = tickers - security_map.keys
    puts "  Skipped:  #{unresolved.to_a.first(20).join(', ')}#{unresolved.size > 20 ? ' ...' : ''}" if unresolved.any?

    abort "ERROR: No securities could be resolved." if security_map.empty?

    # ── Step 4: Stream CSV → temp table ───────────────────────
    puts "\n[4/5] Loading CSV into temp table..."
    conn = ActiveRecord::Base.connection.raw_connection
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    conn.exec("DROP TABLE IF EXISTS tmp_hist_prices")
    conn.exec(<<~SQL)
      CREATE TEMP TABLE tmp_hist_prices (
        ticker     TEXT,
        date_str   TEXT,
        open_val   TEXT,
        high_val   TEXT,
        low_val    TEXT,
        close_val  TEXT,
        volume_val TEXT
      )
    SQL

    row_count = 0
    batch = []
    batch_size = 5_000

    # Map optional headers (nil if column doesn't exist)
    h_date   = hdr["date"]
    h_open   = hdr["open"]
    h_high   = hdr["high"]
    h_low    = hdr["low"]
    h_close  = hdr["close"]
    h_volume = hdr["volume"]

    CSV.foreach(file_path, headers: true, col_sep: col_sep, liberal_parsing: true) do |row|
      ticker = row[ticker_header]&.strip&.upcase
      next if ticker.blank? || !security_map.key?(ticker)

      batch << [
        ticker,
        row[h_date]&.strip,
        h_open   ? row[h_open]&.strip   : nil,
        h_high   ? row[h_high]&.strip   : nil,
        h_low    ? row[h_low]&.strip    : nil,
        row[h_close]&.strip,
        h_volume ? row[h_volume]&.strip : nil
      ]

      if batch.size >= batch_size
        insert_batch(conn, batch)
        row_count += batch.size
        print "\r  #{row_count} rows..."
        batch = []
      end
    end

    if batch.any?
      insert_batch(conn, batch)
      row_count += batch.size
    end

    elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0).round(2)
    puts "\n  Loaded #{row_count} rows in #{elapsed}s"

    if row_count == 0
      conn.exec("DROP TABLE IF EXISTS tmp_hist_prices")
      abort "ERROR: No valid rows found after filtering. Check ticker names."
    end

    # ── Step 5: Upsert temp → historical_prices ──────────────
    puts "\n[5/5] Upserting into historical_prices..."
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    values_list = security_map.map { |tk, id| "('#{tk}', '#{id}'::uuid)" }.join(", ")

    result = conn.exec(<<~SQL)
      INSERT INTO historical_prices
        (id, family_id, security_id, date, open, high, low, close, volume,
         ticker, currency, created_at, updated_at)
      SELECT
        gen_random_uuid(),
        '#{family.id}'::uuid,
        sm.security_id,
        t.date_str::date,
        NULLIF(t.open_val,   '')::numeric,
        NULLIF(t.high_val,   '')::numeric,
        NULLIF(t.low_val,    '')::numeric,
        NULLIF(t.close_val,  '')::numeric,
        NULLIF(t.volume_val, '')::numeric,
        t.ticker,
        '#{family.currency}',
        NOW(), NOW()
      FROM tmp_hist_prices t
      INNER JOIN (VALUES #{values_list}) AS sm(ticker, security_id)
        ON t.ticker = sm.ticker
      WHERE t.date_str IS NOT NULL
        AND t.close_val IS NOT NULL
        AND t.close_val != ''
      ON CONFLICT (family_id, security_id, date) DO UPDATE SET
        open       = EXCLUDED.open,
        high       = EXCLUDED.high,
        low        = EXCLUDED.low,
        close      = EXCLUDED.close,
        volume     = EXCLUDED.volume,
        updated_at = NOW()
    SQL

    elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0).round(2)
    upserted = result.cmd_tuples

    conn.exec("DROP TABLE IF EXISTS tmp_hist_prices")

    puts "  Upserted #{upserted} records in #{elapsed}s"
    puts "\n#{'=' * 60}"
    puts "Done! #{upserted} price records for #{security_map.size} securities."
    puts "=" * 60
  end

  # Batch INSERT into temp table using multi-value SQL
  def self.insert_batch(conn, batch)
    return if batch.empty?

    values_sql = batch.map do |row|
      "(" + row.map { |v| v.nil? ? "NULL" : conn.escape_literal(v) }.join(",") + ")"
    end.join(",")

    conn.exec(
      "INSERT INTO tmp_hist_prices (ticker, date_str, open_val, high_val, low_val, close_val, volume_val) VALUES #{values_sql}"
    )
  end
end
