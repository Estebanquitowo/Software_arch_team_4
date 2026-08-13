require "test_helper"

class AuthorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Book.delete_all
    Author.delete_all
    @author = Author.create!(name: "Jane Doe", country_of_origin: "UK",
                             date_of_birth: Date.new(1980, 1, 1), short_description: "Writer")
  end

  test "should get index" do
    get authors_url
    assert_response :success
  end

  test "returns authors and their books as JSON" do
    Book.create!(title: "Test Book", summary: "A summary.", author: @author)

    get authors_url(format: :json)

    assert_response :success
    author = JSON.parse(response.body).find { |item| item["id"] == @author.id.to_s }
    assert_equal "Jane Doe", author["name"]
    assert_equal [ "Test Book" ], author["books"].pluck("title")
  end

  test "should get new" do
    get new_author_url
    assert_response :success
  end

  test "should create author" do
    assert_difference("Author.count") do
      post authors_url, params: { author: { country_of_origin: @author.country_of_origin, date_of_birth: @author.date_of_birth, name: @author.name, short_description: @author.short_description } }
    end

    assert_redirected_to author_url(Author.last)
  end

  test "should show author" do
    get author_url(@author)
    assert_response :success
  end

  test "should get edit" do
    get edit_author_url(@author)
    assert_response :success
  end

  test "should update author" do
    patch author_url(@author), params: { author: { country_of_origin: @author.country_of_origin, date_of_birth: @author.date_of_birth, name: @author.name, short_description: @author.short_description } }
    assert_redirected_to author_url(@author)
  end

  test "should destroy author" do
    assert_difference("Author.count", -1) do
      delete author_url(@author)
    end

    assert_redirected_to authors_url
  end
end
