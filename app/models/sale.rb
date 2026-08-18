class Sale
  include Mongoid::Document
  include Mongoid::Timestamps
  embedded_in :book

  field :year, type: Integer
  field :units_sold, type: Integer, default: 0
  field :revenue, type: Float, default: 0.0

  validates :year, presence: true, numericality: { only_integer: true }
  validates :units_sold, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :revenue, presence: true, numericality: { greater_than_or_equal_to: 0 }

  after_save :sync_book_sales_count
  after_destroy :sync_book_sales_count

  private

  def sync_book_sales_count
    book.recalculate_sales_count! if book
  end
end
