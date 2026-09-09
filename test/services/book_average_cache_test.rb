require_relative "../support/regression_helper"

class BookAverageCacheTest < ActiveSupport::TestCase
  include RegressionHelper

  setup do
    @previous_cache = Rails.cache
    @previous_cache_flag = ENV["CACHE_ENABLED"]
    ENV["CACHE_ENABLED"] = "true"
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    cleanup_regression_records
    Rails.cache = @previous_cache
    ENV["CACHE_ENABLED"] = @previous_cache_flag
  end

  %w[create update destroy].each do |mutation|
    test "individual average is read through cached and invalidated on review #{mutation}" do
      book = regression_book
      book.reviews.create!(rating: 5, title: "A", content: "A", reviewer_name: "A")
      book.reviews.create!(rating: 1, title: "B", content: "B", reviewer_name: "B")
      # Proposed public read API, intentionally NOT implemented in production.
      # Book owns the average; its reader should delegate cache policy to CacheService.
      assert_respond_to book, :average_review_score, "Missing per-book read-through API (not Book#avg_score stored in MongoDB)"

      writes = []
      hits = []
      on_write = ->(*args) { writes << ActiveSupport::Notifications::Event.new(*args).payload }
      on_hit = ->(*args) { hits << ActiveSupport::Notifications::Event.new(*args).payload }
      ActiveSupport::Notifications.subscribed(on_write, "cache_write.active_support") do
        ActiveSupport::Notifications.subscribed(on_hit, "cache_fetch_hit.active_support") do
          assert_equal 3.0, book.average_review_score
          assert_equal 1, writes.size, "First read must populate its own cache entry"
          key = writes.first.fetch(:key)
          assert_includes key.to_s, book.id.to_s, "Average key must identify this book"
          assert_equal 3.0, Rails.cache.read(key)
          assert_equal 3.0, Book.find(book.id).average_review_score
          assert_equal 1, writes.size, "Second read must not regenerate the cached average"
          assert_equal key, hits.last&.fetch(:key)

          other = regression_book
          other.reviews.create!(rating: 2, title: "Other", content: "Other", reviewer_name: "Other")
          assert_equal 2.0, other.average_review_score
          assert_not_equal key, writes.last.fetch(:key), "Different books must not share an average key"
          book = Book.find(book.id)
          assert_equal 3.0, book.average_review_score
          assert Rails.cache.exist?(key), "Warm the original key again after creating the other book"
          case mutation
          when "create"
            book.reviews.create!(rating: 2, title: "C", content: "C", reviewer_name: "C")
            expected = 2.67
          when "update"
            book.reviews.find_by(rating: 1).update!(rating: 3)
            expected = 4.0
          when "destroy"
            book.reviews.find_by(rating: 1).destroy!
            expected = 5.0
          end
          assert_not Rails.cache.exist?(key), "Review #{mutation} must invalidate the individual average"
          assert_equal expected, Book.find(book.id).average_review_score
          assert_equal expected, Rails.cache.read(key), "The next read must refill from current reviews"
        end
      end
    end
  end
end
