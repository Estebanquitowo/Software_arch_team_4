module CacheInvalidationService
  def self.call(keys: [])
    # Must run even when CACHE_ENABLED=false: data can change while Redis is not
    # used, and those old entries must remain invalid when caching is re-enabled.
    version = CacheGeneration.advance!

    # Optional physical cleanup, only AFTER durable logical invalidation. The
    # configured RedisCacheStore handles Redis/network errors and logs through
    # its error_handler; do not rescue MongoDB errors or change cache backends.
    # A late reader may repopulate an old version after DELETE: versioning, not
    # physical absence, remains the consistency guarantee; TTL bounds retention.
    keys.each { |key| Rails.cache.delete(key) } if CacheService.enabled?
    version
  end
end
