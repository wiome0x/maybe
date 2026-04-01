# frozen_string_literal: true

namespace :logos do
  desc "Download logos for Plaid institutions and stock holdings to local static assets"
  task download: :environment do
    require "open-uri"
    require "fileutils"

    inst_dir = Rails.root.join("app", "assets", "images", "institutions")
    stock_dir = Rails.root.join("app", "assets", "images", "stocks")
    FileUtils.mkdir_p(inst_dir)
    FileUtils.mkdir_p(stock_dir)

    downloaded = 0
    skipped = 0
    failed = 0

    # 1. Plaid institution logos (by domain)
    puts "=== Institution Logos ==="
    PlaidItem.all.each do |item|
      domain = extract_domain(item.institution_url)
      next unless domain.present?

      filename = "#{domain.gsub('.', '_')}.png"
      filepath = inst_dir.join(filename)

      if File.exist?(filepath) && File.size(filepath) > 100
        skipped += 1
        next
      end

      urls = [
        "https://logo.clearbit.com/#{domain}",
        "https://www.google.com/s2/favicons?domain=#{domain}&sz=128"
      ]

      if try_download(urls, filepath)
        downloaded += 1
      else
        puts "  FAIL #{domain}"
        failed += 1
      end
    end

    # 2. Stock/holding logos (by ticker from Finnhub)
    puts "\n=== Stock Logos ==="
    tickers = Security.pluck(:ticker).uniq.compact
    tickers.each do |ticker|
      filename = "#{ticker.upcase}.png"
      filepath = stock_dir.join(filename)

      if File.exist?(filepath) && File.size(filepath) > 100
        skipped += 1
        next
      end

      urls = [
        "https://static2.finnhub.io/file/publicdatany/finnhubimage/stock_logo/#{ticker.upcase}.png"
      ]

      if try_download(urls, filepath)
        downloaded += 1
      else
        failed += 1
      end
    end

    puts "\nDone: #{downloaded} downloaded, #{skipped} skipped, #{failed} failed"
  end
end

def extract_domain(url)
  return nil unless url.present?
  URI.parse(url).host&.gsub(/^www\./, "")
rescue URI::InvalidURIError
  nil
end

def try_download(urls, filepath)
  urls.each do |url|
    begin
      data = URI.open(url, read_timeout: 10).read
      if data.bytesize > 100
        File.binwrite(filepath, data)
        puts "  OK   #{File.basename(filepath)} (#{(data.bytesize / 1024.0).round(1)}KB)"
        return true
      end
    rescue => e
      next
    end
  end
  false
end
