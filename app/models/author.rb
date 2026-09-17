class Author
  include Mongoid::Document
  include Mongoid::Timestamps
  field :name, type: String
  field :date_of_birth, type: Date
  field :country_of_origin, type: String
  field :short_description, type: String
  field :image, type: String
  attr_accessor :image_upload

  has_many :books

  index({ name: 1 }, background: true)

  validates :name, presence: true
  validate :image_upload_is_valid

  after_save :invalidate_derived_cache
  after_destroy :invalidate_derived_cache

  private

  def image_upload_is_valid
    return if image_upload.blank? || ImageStorage.valid_upload?(image_upload)

    errors.add(:image, "must be a JPG, PNG, GIF or WebP image up to 5 MB")
  end

  def invalidate_derived_cache
    CacheInvalidationService.call
  end
end
