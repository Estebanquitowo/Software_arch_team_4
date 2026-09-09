require_relative "../support/regression_helper"

class CachePurgeTest < ActiveSupport::TestCase
  setup do
    raise "Requires an isolated test database" unless Rails.env.test? && Mongoid.default_client.database.name.end_with?("_test")

    @previous_cache = Rails.cache
    @previous_flag = ENV["CACHE_ENABLED"]
    ENV["CACHE_ENABLED"] = "true"
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Rails.cache = @previous_cache
    ENV["CACHE_ENABLED"] = @previous_flag
  end

  test "generation advances before purge and only the supplied key is physically removed" do
    key = "books/one/average_review_score"
    unrelated_key = "books/two/average_review_score"
    CacheService.fetch(key) { 5.0 }
    CacheService.fetch(unrelated_key) { 1.0 }
    before = CacheGeneration.current_version
    observed = []
    Rails.cache.define_singleton_method(:delete) do |deleted_key|
      observed << [ deleted_key, CacheGeneration.current_version ]
      super(deleted_key)
    end
    result = CacheInvalidationService.call(keys: [ key ])
    assert_not_equal before, result
    assert_equal [ [ key, result ] ], observed
    assert_not Rails.cache.exist?(key)
    assert Rails.cache.exist?(unrelated_key)
  end

  test "MongoDB generation errors propagate without attempting purge" do
    key = "books/one/average_review_score"
    CacheService.fetch(key) { 5.0 }
    original_advance = CacheGeneration.method(:advance!)
    error = Mongo::Error::OperationFailure.new("Simulated MongoDB generation failure")
    CacheGeneration.define_singleton_method(:advance!) { raise error }
    raised = assert_raises(Mongo::Error::OperationFailure) { CacheInvalidationService.call(keys: [ key ]) }
    assert_same error, raised
    assert Rails.cache.exist?(key)
  ensure
    CacheGeneration.define_singleton_method(:advance!, original_advance) if original_advance
  end

  test "a late cache writer after purge still cannot publish an old value as current" do
    key = "books/one/average_review_score"
    previous = CacheGeneration.current_version
    CacheService.fetch(key) do
      CacheInvalidationService.call(keys: [ key ])
      5.0
    end
    current = CacheGeneration.current_version
    assert_not_equal previous, current
    assert_equal 5.0, Rails.cache.read(key, version: previous)
    assert_not Rails.cache.exist?(key, version: current)
    assert_equal 1.0, CacheService.fetch(key) { 1.0 }
    assert_equal 1.0, Rails.cache.read(key, version: current)
  end
end
