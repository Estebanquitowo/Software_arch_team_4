require "test_helper"
require "tmpdir"

class AuthorsImageUploadTest < ActionDispatch::IntegrationTest
  setup do
    Book.delete_all
    Author.delete_all
    @tmpdir = Dir.mktmpdir("images-author-upload-test")
    @original_path = ENV["IMAGE_STORAGE_PATH"]
    ENV["IMAGE_STORAGE_PATH"] = @tmpdir
  end

  teardown do
    ENV["IMAGE_STORAGE_PATH"] = @original_path
    FileUtils.remove_entry(@tmpdir)
  end

  def image_fixture
    file = Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/cover.png"),
      "image/png"
    )
    file.define_singleton_method(:original_filename) { "cover.png" }
    file
  end

  test "creates an author with an uploaded image" do
    assert_difference("Author.count", 1) do
      post authors_url, params: { author: {
        name: "Jane Doe", image: image_fixture
      } }
    end

    assert_redirected_to author_url(Author.last)
    author = Author.last
    assert_match(/\Aauthors\/[0-9a-f]+\.png\z/, author.image)
    assert ImageStorage.exist?(author.image)
  end

  test "rejects an invalid image upload" do
    bad = Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/cover.png"),
      "text/plain"
    )
    bad.define_singleton_method(:original_filename) { "notes.txt" }

    assert_no_difference("Author.count") do
      post authors_url, params: { author: { name: "Jane Doe", image: bad } }
    end

    assert_response :unprocessable_content
  end

  test "replaces image on update and removes the previous file" do
    post authors_url, params: { author: { name: "Jane", image: image_fixture } }
    author = Author.last
    first_relative = author.image

    patch author_url(author), params: { author: { name: "Jane", image: image_fixture } }

    assert_redirected_to author_url(author)
    author.reload
    assert_not_equal first_relative, author.image
    assert ImageStorage.exist?(author.image)
    assert_not ImageStorage.exist?(first_relative)
  end

  test "removes image with the remove_image flag" do
    post authors_url, params: { author: { name: "Jane", image: image_fixture } }
    author = Author.last
    assert ImageStorage.exist?(author.image)

    patch author_url(author), params: { author: { name: "Jane", remove_image: "1" } }

    assert_redirected_to author_url(author)
    author.reload
    assert_nil author.image
  end

  test "serves the stored author image" do
    post authors_url, params: { author: { name: "Jane", image: image_fixture } }
    author = Author.last

    get "/images/#{author.image}"

    assert_response :success
    assert_equal "image/png", response.media_type
  end
end