class MarketNewsArticle < ApplicationRecord
  validates :source, :title, :url, :fetched_at, presence: true

  scope :recent_first, -> { order(published_at: :desc, created_at: :desc) }

  def self.latest_feed(limit: MarketNewsFeed::ITEM_LIMIT)
    recent_first.limit(limit).map(&:to_feed_item)
  end

  def self.refresh_if_stale!(ttl: MarketNewsFeed::CACHE_TTL)
    MarketNewsImporter.new.import if stale?(ttl: ttl)
  end

  def self.stale?(ttl: MarketNewsFeed::CACHE_TTL)
    maximum(:fetched_at).blank? || maximum(:fetched_at) < ttl.ago
  end

  def to_feed_item
    MarketNewsFeed::Item.new(
      source: source,
      title: title,
      url: url,
      published_at: published_at,
      translated_title: translated_title
    )
  end
end
