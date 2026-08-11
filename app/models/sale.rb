class Sale
  include Mongoid::Document
  embedded_in :book

  field :year, type: Integer
  field :units_sold, type: Integer
  field :revenue, type: Float

  validates :year, presence: true
  validates :units_sold, :revenue, numericality: { greater_than_or_equal_to: 0 }
end
