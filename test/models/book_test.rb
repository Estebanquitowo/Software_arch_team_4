require "test_helper"

class BookTest < ActiveSupport::TestCase
  setup do
    Author.delete_all
    Book.delete_all
  end

  test "is valid with title and summary" do
    author = Author.create!(name: "Jane Doe")
    book = Book.new(title: "The Test Book", summary: "A summary.", author: author)

    assert book.valid?
  end

  test "requires title and summary" do
    book = Book.new

    assert_not book.valid?
    assert book.errors[:title].any?
    assert book.errors[:summary].any?
  end

  test "belongs to an author and embeds reviews and sales" do
    author = Author.create!(name: "Jane Doe")
    book = Book.create!(title: "The Test Book", summary: "A summary.", author: author)
    book.sales.create!(year: 2020, units_sold: 100, revenue: 500.0)
    book.reviews.create!(rating: 5, title: "Great", content: "Loved it", reviewer_name: "Bob")
    book.reload

    assert_equal author, book.author
    assert_equal 1, book.sales.count
    assert_equal 1, book.reviews.count
    assert_equal 5.0, book.avg_score
  end
end
