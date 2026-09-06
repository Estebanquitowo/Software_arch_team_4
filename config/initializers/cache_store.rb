redis_url = ENV["REDIS_URL"].presence || ENV["CACHE_URL"].presence
cache_enabled = ENV.fetch("CACHE_ENABLED", redis_url ? "true" : "false")

if cache_enabled == "true" && redis_url
  begin
    require "redis"
    redis = Redis.new(url: redis_url)
    redis.ping
    store_opts = {
      url: redis_url,
      reconnect_attempts: 1,
      error_handler: ->(method:, returning:, exception:) {
        Rails.logger.warn("[Cache] Redis error in #{method}: #{exception.class} #{exception.message} - falling back to memory")
      }
    }
    Rails.application.config.cache_store = :redis_cache_store, store_opts
    # bootstrap.rb (:initialize_cache) runs before load_config_initializers
    # and memoizes Rails.cache with the old config (memory_store in development).
    # We must reassign Rails.cache so it uses the new store.
    Rails.cache = ActiveSupport::Cache.lookup_store(:redis_cache_store, **store_opts)
    Rails.logger.info("[Cache] Using RedisCacheStore at #{redis_url}")
  rescue LoadError, StandardError => e
    Rails.logger.warn("[Cache] Redis unavailable (#{e.message}), falling back to :memory_store")
    Rails.application.config.cache_store = :memory_store
    Rails.cache = ActiveSupport::Cache.lookup_store(:memory_store)
  end
elsif cache_enabled == "true"
  Rails.application.config.cache_store = :memory_store
  Rails.cache = ActiveSupport::Cache.lookup_store(:memory_store) unless Rails.cache.is_a?(ActiveSupport::Cache::MemoryStore)
  Rails.logger.info("[Cache] CACHE_ENABLED=true without REDIS_URL -> :memory_store")
else
  default_store = Rails.env.test? ? :null_store : :memory_store
  unless Rails.application.config.cache_store
    Rails.application.config.cache_store = default_store
    Rails.cache = ActiveSupport::Cache.lookup_store(default_store)
  end
  Rails.logger.info("[Cache] Cache disabled or not configured -> #{Rails.application.config.cache_store}")
end

module CacheService
  CACHE_TTL = {
    books_index: 5.minutes,
    authors_summary: 10.minutes,
    top_rated: 10.minutes,
    top_selling: 10.minutes,
    search: 2.minutes
  }.freeze

  def self.fetch(key, expires_in: 5.minutes, &block)
    Rails.cache.fetch(key, expires_in: expires_in, &block)
  rescue StandardError => e
    Rails.logger.warn("[Cache] fetch failed for #{key}: #{e.message}")
    block.call if block
  end

  def self.delete_matched(pattern)
    if Rails.cache.respond_to?(:delete_matched)
      Rails.cache.delete_matched(pattern)
    else
      Rails.cache.clear
    end
  rescue StandardError => e
    Rails.logger.warn("[Cache] delete_matched failed: #{e.message}")
  end

  def self.enabled?
    !Rails.cache.is_a?(ActiveSupport::Cache::NullStore)
  end
end

Rails.application.config.after_initialize do
  if defined?(Book)
    Book.class_eval do
      after_save :_expire_book_caches
      after_destroy :_expire_book_caches

      private

      def _expire_book_caches
        CacheService.delete_matched("books/*")
        CacheService.delete_matched("reports/*")
        CacheService.delete_matched("search/*")
        Rails.cache.delete("authors_summary/*") rescue nil
      end
    end
  end

  if defined?(Author)
    Author.class_eval do
      after_save :_expire_author_caches
      after_destroy :_expire_author_caches

      private

      def _expire_author_caches
        CacheService.delete_matched("reports/*")
        CacheService.delete_matched("authors/*")
      end
    end
  end
end
