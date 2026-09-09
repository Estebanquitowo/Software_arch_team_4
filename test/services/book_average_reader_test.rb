require_relative "../support/regression_helper"

class BookAverageReaderTest < ActiveSupport::TestCase
  include RegressionHelper

  setup do
    @previous_cache = Rails.cache
    @previous_flag = ENV["CACHE_ENABLED"]
    ENV["CACHE_ENABLED"] = "true"
    # Test-only backend, just as in BookAverageCacheTest; production never
    # falls back to MemoryStore. The network scenario below uses real Redis.
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    cleanup_regression_records
    Rails.cache = @previous_cache
    ENV["CACHE_ENABLED"] = @previous_flag
  end

  test "nil is cached as a hit with the configured TTL" do
    book = regression_book
    cache_events do |writes, hits|
      assert_nil book.average_review_score
      assert_nil book.average_review_score
      assert_equal 1, writes.size
      assert_equal 1, hits.size
      assert_equal 600, writes.first.fetch(:expires_in)
      assert Rails.cache.exist?(writes.first.fetch(:key), version: CacheGeneration.current_version)
    end
  end

  test "a stale book reads the persisted score without overwriting pending attributes" do
    book = regression_book
    review = book.reviews.create!(rating: 5, title: "A", content: "A", reviewer_name: "A")
    stale = Book.find(book.id)
    stale.title = "Unsaved title"
    review.update!(rating: 1)
    assert_equal 5.0, stale.avg_score
    assert_equal 1.0, stale.average_review_score
    assert_equal 1.0, Rails.cache.read("books/#{book.id}/average_review_score", version: CacheGeneration.current_version)
    assert_equal "Unsaved title", stale.title
    assert stale.changed?
  end

  test "review mutations invalidate the current version even when physical purge fails" do
    # Deliberately retain the old entry: consistency must not depend on DELETE.
    # This is a test-only failure double; real Redis outages are tested below.
    Rails.cache = Class.new(ActiveSupport::Cache::MemoryStore) do
      def delete(*)
        false
      end
    end.new
    book = regression_book
    key = "books/#{book.id}/average_review_score"
    assert_nil book.average_review_score
    review = nil
    changes = [
      [ 5.0, -> { review = book.reviews.create!(rating: 5, title: "A", content: "A", reviewer_name: "A") } ],
      [ 1.0, -> { review.update!(rating: 1) } ],
      [ nil, -> { review.destroy! } ]
    ]
    changes.each do |expected, change|
      old_version = CacheGeneration.current_version
      change.call
      current_version = CacheGeneration.current_version
      assert_not_equal old_version, current_version
      assert Rails.cache.exist?(key, version: old_version)
      assert_not Rails.cache.exist?(key, version: current_version)
      actual = book.average_review_score
      expected.nil? ? assert_nil(actual) : assert_equal(expected, actual)
      assert Rails.cache.exist?(key, version: current_version)
    end
  end

  test "disabled cache bypasses a previously cached average on every read" do
    book = regression_book
    review = book.reviews.create!(rating: 5, title: "A", content: "A", reviewer_name: "A")
    assert_equal 5.0, book.average_review_score
    key = "books/#{book.id}/average_review_score"
    old_version = CacheGeneration.current_version
    ENV["CACHE_ENABLED"] = "false"
    review.update!(rating: 1)
    cache_events do |writes, hits|
      assert_equal 1.0, book.average_review_score
      review.update!(rating: 2)
      assert_equal 2.0, book.average_review_score
      assert_empty writes
      assert_empty hits
    end
    assert_equal 5.0, Rails.cache.read(key, version: old_version), "Bypass must not read or delete the old physical entry"
  end

  test "real Redis caches nil and recovers the current average after an outage" do
    result = scenario("average_redis")
    assert result.fetch("nil_cached")
    assert_equal 1, result.fetch("nil_hits")
    assert_equal 5.0, result.fetch("warm")
    assert_equal 1.0, result.fetch("offline")
    assert_equal 5.0, result.fetch("stranded")
    assert_equal 1.0, result.fetch("recovered")
    assert_equal 1.0, result.fetch("redis_value")
    assert_equal 1.0, result.fetch("second_read")
    assert_equal 1, result.fetch("recovered_hits")
    assert_equal 200, result.fetch("page_status")
    assert_equal 303, result.fetch("write_status"), "Redis purge failure must not turn the review update into HTTP 500"
    assert result.fetch("generation_advanced")
    assert result.fetch("purge_warning")
    assert result.fetch("purged_create")
    assert result.fetch("purged_update")
    assert result.fetch("purged_destroy")
    assert_equal 1.0, result.fetch("updated_average")
    assert_nil result.fetch("empty_average")
    assert result.fetch("empty_cached")
  end

  private

  def cache_events
    writes = []
    hits = []
    on_write = ->(*args) { writes << ActiveSupport::Notifications::Event.new(*args).payload }
    on_hit = ->(*args) { hits << ActiveSupport::Notifications::Event.new(*args).payload }
    ActiveSupport::Notifications.subscribed(on_write, "cache_write.active_support") do
      ActiveSupport::Notifications.subscribed(on_hit, "cache_fetch_hit.active_support") do
        yield writes, hits
      end
    end
  end
end
