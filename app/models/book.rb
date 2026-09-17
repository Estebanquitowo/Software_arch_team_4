class Book
  include Mongoid::Document
  include Mongoid::Timestamps

  belongs_to :author, index: true
  embeds_many :reviews
  embeds_many :sales

  field :title, type: String
  field :summary, type: String
  field :publication_date, type: Date
  field :publication_year, type: Integer
  field :avg_score, type: Float
  field :number_of_sales, type: Integer, default: 0
  field :cover_image, type: String

  attr_accessor :cover_image_upload
  validates :title, :summary, presence: true
  validate :cover_image_upload_is_valid

  index({ summary: "text" }, background: true)
  index({ publication_date: 1 }, background: true)
  index({ "sales.year" => 1 }, background: true)

  after_save :invalidate_derived_cache
  after_destroy :invalidate_derived_cache
  after_commit :sync_search_change, on: %i[create update]
  after_commit :sync_search_deletion, on: :destroy

  if ENV.fetch("SEARCH_ENABLED", "false") == "true" && ENV["MEILISEARCH_URL"].present?
    begin
      require "meilisearch-rails"
      include MeiliSearch::Rails

      meilisearch synchronous: true,
                  auto_index: false, auto_remove: false,
                  index_uid: "books" do
        attribute :title, :summary, :publication_year, :avg_score, :number_of_sales
        attribute :author_name do
          author&.name
        end
        attribute :review_text do
          reviews.reject(&:destroyed?).map { |r| [ r.title, r.content ].compact.join(" ") }.join(" ")
        end
        searchable_attributes [ :title, :summary, :author_name, :review_text ]
        filterable_attributes [ :publication_year ]
        sortable_attributes [ :publication_year, :avg_score ]
      end
    rescue LoadError, StandardError => e
      Rails.logger.warn("[Search] Meilisearch include failed: #{e.message}") if defined?(Rails)
    end
  end

  def recalculate_sales_count!
    BookStatisticsRecalculator.recalculate_sales(id)
  end

  def recalculate_avg_score!
    BookStatisticsRecalculator.recalculate_average(id)
  end

  def average_review_score
    CacheService.fetch(Book.average_review_score_cache_key(id), expires_in: CacheService::CACHE_TTL[:average_review_score]) do
      # Read only the persisted statistic, never this instance's stale attributes
      # or embedded reviews. A missing score (including no reviews) remains nil.
      Book.where(id: id).limit(1).pluck(:avg_score).first
    end
  end

  def self.average_review_score_cache_key(book_id)
    "books/#{book_id}/average_review_score"
  end

  private

  def cover_image_upload_is_valid
    return if cover_image_upload.blank? || ImageStorage.valid_upload?(cover_image_upload)

    errors.add(:cover_image, "must be a JPG, PNG, GIF or WebP image up to 5 MB")
  end

  def sync_search_change
    SearchSyncService.book_changed(id)
  end

  def sync_search_deletion
    SearchSyncService.book_deleted(id)
  end

  def invalidate_derived_cache
    CacheInvalidationService.call
  end
end
