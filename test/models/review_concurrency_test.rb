require_relative "../support/regression_helper"

class ReviewConcurrencyTest < ActiveSupport::TestCase
  include RegressionHelper
  teardown { cleanup_regression_records }

  test "average includes both persisted reviews from stale request instances" do
    book = regression_book
    first = Book.find(book.id)
    second = Book.find(book.id)
    # Deterministic schedule: A reads []; B reads []; A writes 5; B writes 1.
    # No shared Mongoid instance, threads, sleeps, or scheduler luck are needed.
    first.reviews.to_a
    second.reviews.to_a
    first.reviews.create!(rating: 5, title: "A", content: "A", reviewer_name: "A")
    second.reviews.create!(rating: 1, title: "B", content: "B", reviewer_name: "B")

    fresh = Book.find(book.id)
    assert_equal [ 1, 5 ], fresh.reviews.map(&:rating).sort
    assert_equal 3.0, fresh.avg_score, "Both reviews persisted, but the derived average used stale state"
  end
end
