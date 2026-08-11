class Review
  include Mongoid::Document
  embedded_in :book

  field :rating, type: Integer
  field :title, type: String
  field :content, type: String
  field :reviewer_name, type: String

  validates :rating, presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 5 }
  validates :title, :content, :reviewer_name, presence: true

  after_save :recalculate_book_avg_score
  after_destroy :recalculate_book_avg_score

  private

  # Recomputes Book#avg_score whenever a review is added/edited/removed.
  # Uses the in-memory relation (excluding the just-destroyed doc) so it's
  # correct regardless of callback ordering, and only touches the DB once.
  def recalculate_book_avg_score
    book = _parent #to test
    return unless book.persisted?

    ratings = book.reviews.reject(&:destroyed?).map(&:rating).compact
    book.avg_score = ratings.empty? ? nil : (ratings.sum.to_f / ratings.size).round(2)
    book.save!(validate: false)
  end
end