module CacheInvalidationService
  def self.call
    # Must run even when CACHE_ENABLED=false: data can change while Redis is not
    # used, and those old entries must remain invalid when caching is re-enabled.
    CacheGeneration.advance!
  end
end
