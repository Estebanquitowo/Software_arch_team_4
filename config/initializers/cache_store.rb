require "digest"

redis_url = ENV["REDIS_URL"].presence || ENV["CACHE_URL"].presence
cache_enabled = ENV.fetch("CACHE_ENABLED", "false") == "true"

if cache_enabled && redis_url
  require "redis"
  database_uri = Rails.env.test? ? ENV["MONGODB_TEST_URI"] : ENV["MONGODB_URI"]
  # A new schema namespace excludes legacy entries without a native version.
  # Hash connection identity rather than exposing credentials in Redis keys.
  namespace = "software_arch_team4/cache-v2/#{Rails.env}/#{Digest::SHA256.hexdigest(database_uri.to_s)[0, 16]}"
  options = {
    url: redis_url,
    namespace: namespace,
    connect_timeout: 0.5,
    read_timeout: 0.5,
    write_timeout: 0.5,
    reconnect_attempts: 1,
    error_handler: ->(method:, returning:, exception:) {
      Rails.logger.warn("[Cache] Redis #{method} failed (#{exception.class}); cache miss/write dropped")
    }
  }
  Rails.application.config.cache_store = :redis_cache_store, options
  # Rails initializes Rails.cache before loading this initializer. Replace that
  # memoized store, but never select another backend based on network availability.
  Rails.cache = ActiveSupport::Cache.lookup_store(:redis_cache_store, **options)
else
  Rails.application.config.cache_store = :null_store
  Rails.cache = ActiveSupport::Cache.lookup_store(:null_store)
  if cache_enabled
    Rails.logger.warn("[Cache] CACHE_ENABLED=true without REDIS_URL/CACHE_URL; cache bypassed")
  end
end
