require_relative "seeds/hardcover_seeder"
require_relative "seeds/author_details_seeder"
require_relative "seeds/reviews_seeder"
require_relative "seeds/sales_seeder"

HardcoverSeeder.call
AuthorDetailsSeeder.call
ReviewsSeeder.call
SalesSeeder.call

CacheService.clear
puts "[Seeds] Cache generation advanced (logical invalidation)"

if defined?(SearchService) && SearchService.enabled?
  puts "[Seeds] Syncing books to Meilisearch..."
  begin
    Book.reindex!
    puts "[Seeds] Meilisearch reindex done (#{Book.count} books)"
  rescue StandardError => e
    warn "[Seeds] Meilisearch reindex failed: #{e.message} (search will fallback to Mongo)"
  end
end
