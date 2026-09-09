class Author
  include Mongoid::Document
  include Mongoid::Timestamps
  field :name, type: String
  field :date_of_birth, type: Date
  field :country_of_origin, type: String
  field :short_description, type: String

  has_many :books

  index({ name: 1 }, background: true)

  validates :name, presence: true

  after_save :invalidate_derived_cache
  after_destroy :invalidate_derived_cache

  private

  def invalidate_derived_cache
    CacheInvalidationService.call
  end
end
