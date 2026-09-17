require "test_helper"
require "tmpdir"

class ImageStorageTest < ActiveSupport::TestCase
  setup do
    @tmpdir = Dir.mktmpdir("images-test")
    @original_path = ENV["IMAGE_STORAGE_PATH"]
    ENV["IMAGE_STORAGE_PATH"] = @tmpdir
  end

  teardown do
    ENV["IMAGE_STORAGE_PATH"] = @original_path
    FileUtils.remove_entry(@tmpdir)
  end

  def uploaded_file(name: "cover.png", type: "image/png", body: nil)
    body ||= File.binread(Rails.root.join("test/fixtures/files/cover.png"))
    ActionDispatch::Http::UploadedFile.new(
      filename: name,
      type: type,
      tempfile: StringIO.new(body)
    )
  end

  test "stores an image under the configured root and returns a relative path" do
    relative = ImageStorage.store(uploaded_file, kind: "books")

    assert_match(/\Abooks\/[0-9a-f]+\.png\z/, relative)
    assert File.exist?(File.join(@tmpdir, relative))
    assert ImageStorage.exist?(relative)
  end

  test "uses the configured IMAGE_STORAGE_PATH as root" do
    relative = ImageStorage.store(uploaded_file, kind: "authors")

    assert ImageStorage.absolute(relative).start_with?(@tmpdir)
  end

  test "rejects non-image uploads" do
    bad = uploaded_file(name: "notes.txt", type: "text/plain", body: "hello")

    assert_raises(ImageStorage::InvalidUpload) { ImageStorage.store(bad, kind: "books") }
  end

  test "rejects oversized uploads" do
    large = uploaded_file(body: "x" * (ImageStorage::MAX_SIZE + 1))

    assert_raises(ImageStorage::InvalidUpload) { ImageStorage.store(large, kind: "books") }
  end

  test "falls back to content type when the filename has no extension" do
    relative = ImageStorage.store(uploaded_file(name: "cover", type: "image/webp"), kind: "books")

    assert_match(/\.webp\z/, relative)
    assert ImageStorage.exist?(relative)
  end

  test "normalizes jpeg extension" do
    relative = ImageStorage.store(uploaded_file(name: "cover.jpeg", type: "image/jpeg"), kind: "books")

    assert_match(/\.jpg\z/, relative)
  end

  test "deletes stored images" do
    relative = ImageStorage.store(uploaded_file, kind: "books")
    assert ImageStorage.exist?(relative)

    ImageStorage.delete(relative)

    assert_not ImageStorage.exist?(relative)
  end

  test "validates relative paths to prevent traversal" do
    assert_not ImageStorage.valid_relative?("../secret")
    assert_not ImageStorage.valid_relative?("books/../../etc/passwd")
    assert_not ImageStorage.valid_relative?("")
    assert ImageStorage.valid_relative?("books/abc123.png")
  end
end