module CacheService
  CACHE_TTL = {
    books_index: 5.minutes,
    authors_summary: 10.minutes,
    top_rated: 10.minutes,
    top_selling: 10.minutes,
    search: 2.minutes
  }.freeze

  def self.enabled?
    ENV.fetch("CACHE_ENABLED", "false") == "true" &&
      !Rails.cache.is_a?(ActiveSupport::Cache::NullStore)
  end

  def self.fetch(key, expires_in: 5.minutes, &block)
    return block.call unless enabled?

    # Capture ONCE, before reading/calculating: a late writer must retain its old
    # generation, never label an old result with a newer generation.
    version = CacheGeneration.current_version
    Rails.cache.fetch(key, expires_in: expires_in, version: version, &block)
    # RedisCacheStore handles backend outages. Do not rescue the application
    # block (or MongoDB generation errors) and accidentally execute it twice.
  end

  # Clear means logical invalidation across workers, even with Redis offline or
  # cache disabled. Physical eviction is left to TTL; never flush a shared Redis.
  def self.clear
    CacheInvalidationService.call
  end
end
