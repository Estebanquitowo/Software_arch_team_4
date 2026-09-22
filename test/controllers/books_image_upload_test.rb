require "test_helper"
require "tmpdir"

class BooksImageUploadTest < ActionDispatch::IntegrationTest
  setup do
    Book.delete_all
    Author.delete_all
    @author = Author.create!(name: "Jane Doe")
    @tmpdir = Dir.mktmpdir("images-upload-test")
    @original_path = ENV["IMAGE_STORAGE_PATH"]
    ENV["IMAGE_STORAGE_PATH"] = @tmpdir
  end

  teardown do
    ENV["IMAGE_STORAGE_PATH"] = @original_path
    FileUtils.remove_entry(@tmpdir)
  end

  def cover_fixture
    file = Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/cover.png"),
      "image/png"
    )
    file.define_singleton_method(:original_filename) { "cover.png" }
    file
  end

  test "creates a book with an uploaded cover" do
    assert_difference("Book.count", 1) do
      post books_url, params: { book: {
        title: "Covered Book", summary: "Summary", author_id: @author.id.to_s,
        cover_image: cover_fixture
      } }
    end

    assert_redirected_to book_url(Book.last)
    book = Book.last
    assert_match(/\Abooks\/[0-9a-f]+\.png\z/, book.cover_image)
  end

  test "rejects an invalid cover upload" do
    bad = Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/cover.png"),
      "text/plain"
    )
    bad.define_singleton_method(:original_filename) { "notes.txt" }

    assert_no_difference("Book.count") do
      post books_url, params: { book: {
        title: "Bad Book", summary: "Summary", author_id: @author.id.to_s,
        cover_image: bad
      } }
    end

    assert_response :unprocessable_content
  end

  test "replaces cover on update and removes the previous file" do
    book = Book.create!(title: "Original", summary: "Summary", author: @author)
    post books_url, params: { book: {
      title: "Missing File Trigger", summary: "x", author_id: @author.id.to_s,
      cover_image: cover_fixture
    } }
    book = Book.last
    first_relative = book.cover_image
    assert ImageStorage.exist?(first_relative)

    patch book_url(book), params: { book: {
      title: "Original", summary: "Summary", author_id: @author.id.to_s,
      cover_image: cover_fixture
    } }

    assert_redirected_to book_url(book)
    book.reload
    assert_not_equal first_relative, book.cover_image
    assert ImageStorage.exist?(book.cover_image)
    assert_not ImageStorage.exist?(first_relative)
  end

  test "removes cover with the remove_cover_image flag" do
    book = Book.create!(title: "Covered", summary: "Summary", author: @author)
    post books_url, params: { book: {
      title: "Covered2", summary: "S", author_id: @author.id.to_s,
      cover_image: cover_fixture
    } }
    book = Book.last
    assert ImageStorage.exist?(book.cover_image)

    patch book_url(book), params: { book: {
      title: "Covered2", summary: "S", author_id: @author.id.to_s,
      remove_cover_image: "1"
    } }

    assert_redirected_to book_url(book)
    book.reload
    assert_nil book.cover_image
  end

  test "serves the stored image at the images path" do
    book = Book.create!(title: "Covered", summary: "Summary", author: @author)
    post books_url, params: { book: {
      title: "Covered2", summary: "S", author_id: @author.id.to_s,
      cover_image: cover_fixture
    } }
    book = Book.last

    get "/images/#{book.cover_image}"

    assert_response :success
    assert_equal "image/png", response.media_type
  end

  test "returns 404 for traversal attempts" do
    get "/images/../../etc/passwd"

    assert_response :not_found
  end
end