require "test_helper"

class DebugControllerTest < ActionDispatch::IntegrationTest
  setup do
    Book.delete_all
    Author.delete_all

    author = Author.create!(name: "Jane Doe", country_of_origin: "UK", date_of_birth: Date.new(1980, 1, 1))
    book = Book.create!(
      title: "The Test Book",
      summary: "A summary.",
      publication_date: Date.new(2020, 1, 1),
      avg_score: 4.0,
      number_of_sales: 100,
      author: author
    )
    book.reviews.create!(rating: 4, title: "Good", content: "A useful review.", reviewer_name: "Reader")
  end

  test "shows authors, books, and a review sample" do
    get debug_path

    assert_response :success
    assert_select "h1", "MongoDB debug"
    assert_select "td", "Jane Doe"
    assert_select "td", "The Test Book"
    assert_select "td", /A useful review/
  end
end
