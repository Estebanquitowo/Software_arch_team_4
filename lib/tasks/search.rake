namespace :search do
  desc "Reindex all books into Meilisearch (no-op if SEARCH_ENABLED != true)"
  task reindex: :environment do
    unless SearchService.enabled?
      puts "[Search] Meilisearch disabled (SEARCH_ENABLED=#{ENV['SEARCH_ENABLED']}, MEILISEARCH_URL=#{ENV['MEILISEARCH_URL']}) - using Mongo fallback, nothing to reindex."
      next
    end
    count = Book.count
    puts "[Search] Reindexing #{count} books to Meilisearch at #{ENV['MEILISEARCH_URL']}..."
    Book.reindex!
    puts "[Search] Done. Indexed #{count} books."
  rescue StandardError => e
    warn "[Search] Reindex failed: #{e.class}: #{e.message}"
    warn "Falling back to Mongo search will continue to work."
  end

  desc "Clear Meilisearch index"
  task clear: :environment do
    unless SearchService.enabled?
      puts "[Search] Meilisearch disabled - nothing to clear"
      next
    end
    Book.msclear_index!
    puts "[Search] Index cleared"
  end
end

namespace :cache do
  desc "Invalidate derived cache by advancing its MongoDB generation (no Redis flush)"
  task clear: :environment do
    CacheService.clear
    puts "[Cache] Generation advanced; older entries will miss and expire by TTL"
  end
end
