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

  index({ summary: "text" }, background: true)
  index({ publication_date: 1 }, background: true)
  index({ "sales.year" => 1 }, background: true)

  validates :title, :summary, presence: true

  after_save :invalidate_derived_cache
  after_destroy :invalidate_derived_cache

  if ENV.fetch("SEARCH_ENABLED", "false") == "true" && ENV["MEILISEARCH_URL"].present?
    begin
      require "meilisearch-rails"
      include MeiliSearch::Rails

      meilisearch synchronous: true,
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
    total = sales.reject(&:destroyed?).sum { |s| s.units_sold || 0 }
    self.number_of_sales = total
    save!(validate: false)
  end

  private

  def invalidate_derived_cache
    CacheInvalidationService.call
  end
end
