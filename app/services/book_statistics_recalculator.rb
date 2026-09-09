# Each pipeline computes and stores one statistic atomically from the persisted
# embedded documents. The child write, cache invalidation and search indexing
# are separate operations, not a transaction (a crash between them can leave lag).
class BookStatisticsRecalculator
  def self.recalculate_average(book_id)
    ratings = {
      "$filter" => {
        "input" => { "$ifNull" => [ "$reviews.rating", [] ] },
        "as" => "rating", "cond" => { "$ne" => [ "$$rating", nil ] }
      }
    }
    average = {
      "$let" => {
        "vars" => { "ratings" => ratings },
        "in" => {
          "$let" => {
            "vars" => { "total" => { "$sum" => "$$ratings" }, "count" => { "$size" => "$$ratings" } },
            "in" => {
              "$cond" => [
                { "$eq" => [ "$$count", 0 ] }, nil,
                # Positive integer ratings: floor((200 * sum + n) / (2 * n))
                # gives hundredths with Ruby's half-up rounding, not $round's
                # ties-to-even (2.625 must become 2.63). $divide returns Double.
                { "$divide" => [
                  { "$floor" => { "$divide" => [
                    { "$add" => [ { "$multiply" => [ 200, "$$total" ] }, "$$count" ] },
                    { "$multiply" => [ 2, "$$count" ] }
                  ] } }, 100.0
                ] }
              ]
            }
          }
        }
      }
    }
    update_statistic(book_id, "avg_score", average)
  end

  def self.recalculate_sales(book_id)
    update_statistic(book_id, "number_of_sales", { "$sum" => { "$ifNull" => [ "$sales.units_sold", [] ] } })
  end

  def self.update_statistic(book_id, field, expression)
    document = Book.collection.find(_id: book_id).find_one_and_update(
      [ { "$set" => { field => expression, "updated_at" => "$$NOW" } } ],
      upsert: false, return_document: :after
    )
    return unless document

    # Raw driver writes bypass Book callbacks. Publish exactly once, including
    # text-only review edits whose unchanged average still affects cached views.
    CacheInvalidationService.call

    if Book.method_defined?(:ms_index!)
      # Never save/reload the caller's stale parent: it may hold pending edits.
      # A concurrent deletion between the update and this read is harmless.
      Book.where(id: book_id).first&.ms_index!
    end
    document
  end
  private_class_method :update_statistic
end
