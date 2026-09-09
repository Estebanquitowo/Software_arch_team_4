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

  def recalculate_book_avg_score
    # Mongoid unbinds the public association before destroy_all's after callbacks;
    # _parent still identifies the owner. Only its ID is used for recalculation.
    parent = _parent
    parent.recalculate_avg_score! if parent&.persisted?
  end
end
