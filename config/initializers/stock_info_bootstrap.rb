Rails.application.config.after_initialize do
  next unless Rails.env.production?

  StockInfoBootstrap.perform!
end
