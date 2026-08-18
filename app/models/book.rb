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

  def recalculate_sales_count!
    total = sales.sum { |s| s.units_sold || 0 }
    set(number_of_sales: total)
  end
end
