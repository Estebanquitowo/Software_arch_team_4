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
  result = SearchSyncService.reconcile!
  puts "[Seeds] Meilisearch reconciliation: #{result}"
end
