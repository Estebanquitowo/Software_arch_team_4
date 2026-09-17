require "fileutils"

# Stores uploaded images on shared storage so that any application instance
# can read files written by another. The storage root is fully configurable
# through IMAGE_STORAGE_PATH (e.g. /data/images); nothing about the location
# is hardcoded here. The URL prefix (/images/<relative path>) is what the
# reverse proxy uses to serve static assets at the edge.
class ImageStorage
  class InvalidUpload < StandardError; end

  ALLOWED_EXTENSIONS = %w[jpg jpeg png gif webp].freeze
  ALLOWED_CONTENT_TYPES = {
    "image/jpeg" => "jpg",
    "image/png" => "png",
    "image/gif" => "gif",
    "image/webp" => "webp"
  }.freeze
  MAX_SIZE = 5.megabytes
  RELATIVE_PATTERN = %r{\A[a-z]+/[0-9a-f]+\.(jpg|jpeg|png|gif|webp)\z}

  def self.root
    ENV.fetch("IMAGE_STORAGE_PATH", Rails.root.join("storage", "uploads").to_s)
  end

  def self.store(upload, kind:)
    raise InvalidUpload, "must be a JPG, PNG, GIF or WebP image" unless valid_upload?(upload)

    ext = extension_for(upload)
    filename = "#{SecureRandom.hex(8)}.#{ext}"
    relative = "#{kind}/#{filename}"
    dir = File.join(root, kind.to_s)
    FileUtils.mkdir_p(dir)
    File.binwrite(File.join(dir, filename), upload.read)
    relative
  end

  def self.valid_upload?(upload)
    return false unless upload.present? && upload.respond_to?(:original_filename)
    return false unless ALLOWED_CONTENT_TYPES.key?(upload.content_type)
    return false if upload.size > MAX_SIZE

    extension_for(upload).present?
  end

  def self.extension_for(upload)
    ext = File.extname(upload.original_filename.to_s).sub(/\A\./, "").downcase
    return "jpg" if ext == "jpeg"
    return ext if ALLOWED_EXTENSIONS.include?(ext)

    ALLOWED_CONTENT_TYPES[upload.content_type]
  end

  def self.valid_relative?(relative)
    relative.is_a?(String) && relative.match?(RELATIVE_PATTERN) && !relative.include?("..")
  end

  def self.absolute(relative)
    File.expand_path(File.join(root, relative))
  end

  def self.exist?(relative)
    valid_relative?(relative) && File.exist?(absolute(relative))
  end

  def self.delete(relative)
    return unless valid_relative?(relative) && File.exist?(absolute(relative))

    File.delete(absolute(relative))
  end
end
