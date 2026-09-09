require_relative "../support/regression_helper"

class CacheVersioningTest < ActiveSupport::TestCase
  setup do
    raise "Requires an isolated test database" unless Rails.env.test? && Mongoid.default_client.database.name.end_with?("_test")

    @previous_store = Rails.cache
    @previous_flag = ENV["CACHE_ENABLED"]
    ENV["CACHE_ENABLED"] = "true"
    # Explicit test backend, not a production fallback. Rails native versioning
    # is shared by stores; Redis/network behavior has separate integration tests.
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Rails.cache = @previous_store
    ENV["CACHE_ENABLED"] = @previous_flag
  end

  test "an old in flight read cannot be tagged with the new generation" do
    key = "regression/in-flight"
    old_version = CacheGeneration.current_version
    result = CacheService.fetch(key) do
      # Deterministic interleaving: A captured a version and a DB result; B
      # commits invalidation before A finishes writing its result to the cache.
      CacheInvalidationService.call
      "old snapshot"
    end
    assert_equal "old snapshot", result
    new_version = CacheGeneration.current_version
    assert_not_equal old_version, new_version
    assert_equal "old snapshot", Rails.cache.read(key, version: old_version)
    assert_nil Rails.cache.read(key, version: new_version)
    assert_equal "current snapshot", CacheService.fetch(key) { "current snapshot" }
    assert_equal "current snapshot", Rails.cache.read(key, version: new_version)
  end

  test "an application exception is propagated without executing the block twice" do
    calls = 0
    original_error = Class.new(StandardError).new("application failure")
    raised = assert_raises(original_error.class) do
      CacheService.fetch("regression/application-error") do
        calls += 1
        raise original_error
      end
    end
    assert_same original_error, raised
    assert_equal 1, calls
    assert_not Rails.cache.exist?("regression/application-error")
  end
end
