require "test_helper"

class ReviewTest < ActiveSupport::TestCase
  setup do
    Author.delete_all
    Book.delete_all
  end

  def create_book
    author = Author.create!(name: "Jane Doe")
    Book.create!(title: "The Test Book", summary: "A summary.", author: author)
  end

  test "rating must be between 1 and 5" do
    book = create_book
    review = book.reviews.new(rating: 6, title: "Too high", content: "x", reviewer_name: "Bob")

    assert_not review.valid?
    assert review.errors[:rating].any?

    review.rating = 0
    assert_not review.valid?

    review.rating = 3
    assert review.valid?
  end

  test "recalculates avg_score on create and update" do
    book = create_book
    book.reviews.create!(rating: 4, title: "Good", content: "Nice", reviewer_name: "Alice")
    assert_equal 4.0, book.reload.avg_score

    book.reviews.create!(rating: 2, title: "Meh", content: "Okay", reviewer_name: "Bob")
    assert_equal 3.0, book.reload.avg_score

    book.reviews.find_by(rating: 4).update!(rating: 1)
    assert_equal 1.5, book.reload.avg_score
  end

  test "recalculates avg_score on destroy" do
    book = create_book
    book.reviews.create!(rating: 5, title: "A", content: "x", reviewer_name: "Alice")
    book.reviews.create!(rating: 1, title: "B", content: "x", reviewer_name: "Bob")
    assert_equal 3.0, book.reload.avg_score

    book.reviews.find_by(rating: 1).destroy
    assert_equal 5.0, book.reload.avg_score

    book.reviews.destroy_all
    assert_nil book.reload.avg_score
  end
end
