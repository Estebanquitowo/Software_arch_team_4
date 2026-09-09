require_relative "../support/regression_helper"

class BookStatisticsRecalculatorTest < ActiveSupport::TestCase
  include RegressionHelper
  teardown { cleanup_regression_records }

  test "average preserves Ruby half-up rounding and is stored as a float" do
    book = regression_book
    [ 1, 1, 1, 1, 2, 5, 5, 5 ].each { |rating| create_review(book, rating) }

    document = Book.collection.find(_id: book.id).first
    assert_equal 2.63, document.fetch("avg_score")
    assert_instance_of Float, document.fetch("avg_score")
  end

  test "sales lifecycle recalculates integers and publishes one invalidation per change" do
    book = regression_book
    first = second = nil
    assert_one_invalidation { first = book.sales.create!(year: 2020, units_sold: 10) }
    assert_equal 10, book.reload.number_of_sales
    assert_one_invalidation { second = book.sales.create!(year: 2021, units_sold: 20) }
    assert_equal 30, book.reload.number_of_sales
    assert_one_invalidation { first.update!(units_sold: 15) }
    assert_equal 35, book.reload.number_of_sales
    assert_one_invalidation { second.destroy! }
    assert_equal 15, book.reload.number_of_sales
    assert_one_invalidation { first.destroy! }
    document = Book.collection.find(_id: book.id).first
    assert_equal 0, document.fetch("number_of_sales")
    assert_instance_of Integer, document.fetch("number_of_sales")
  end

  test "review lifecycle invalidates even when only content changes" do
    book = regression_book
    review = nil
    assert_one_invalidation { review = create_review(book, 5) }
    assert_equal 5.0, book.reload.avg_score
    assert_one_invalidation { review.update!(rating: 3) }
    assert_equal 3.0, book.reload.avg_score
    assert_one_invalidation { review.update!(content: "Changed review text") }
    assert_equal 3.0, book.reload.avg_score
    assert_equal "Changed review text", book.reviews.first.content
    assert_one_invalidation { review.destroy! }
    assert_nil book.reload.avg_score
  end

  test "repeated recalculations ignore stale associations and never save pending parent edits" do
    book = regression_book
    book.reviews.to_a
    book.sales.to_a
    book.title = "Unsaved title"
    book.avg_score = 99.0
    book.number_of_sales = 999
    writer = Book.find(book.id)
    create_review(writer, 5)
    create_review(writer, 1)
    writer.sales.create!(year: 2020, units_sold: 10)
    writer.sales.create!(year: 2021, units_sold: 20)
    before = Book.collection.find(_id: book.id).first
    old_time = Time.utc(2000)
    Book.collection.find(_id: book.id).update_one("$set" => { "updated_at" => old_time })

    3.times do
      assert_equal 3.0, book.recalculate_avg_score!.fetch("avg_score")
      assert_equal 30, book.recalculate_sales_count!.fetch("number_of_sales")
    end

    after = Book.collection.find(_id: book.id).first
    assert_equal before.except("updated_at"), after.except("updated_at")
    assert_operator after.fetch("updated_at"), :>, old_time
    assert_equal "Unsaved title", book.title
    assert book.changed?, "Recalculation must not discard pending Mongoid edits"
    assert_empty book.reviews.to_a
    assert_empty book.sales.to_a
  end

  test "bulk destroy recalculates after Mongoid unbinds the embedded associations" do
    book = regression_book
    create_review(book, 5)
    create_review(book, 1)
    book.sales.create!(year: 2020, units_sold: 10)
    book.sales.create!(year: 2021, units_sold: 20)
    assert_equal 2, book.reviews.destroy_all
    assert_nil book.reload.avg_score
    assert_equal 30, book.number_of_sales
    assert_equal 2, book.sales.destroy_all
    assert_equal 0, book.reload.number_of_sales
    assert_nil book.avg_score
  end

  test "a deleted book is not recreated or invalidated by recalculation" do
    book = regression_book
    Book.where(id: book.id).delete_all
    version = CacheGeneration.current_version
    assert_nil book.recalculate_avg_score!
    assert_nil book.recalculate_sales_count!
    assert_not Book.where(id: book.id).exists?
    assert_equal version, CacheGeneration.current_version
  end

  test "missing embedded arrays produce nil average and integer zero sales independently" do
    book = regression_book
    book.recalculate_avg_score!
    assert_nil book.reload.avg_score
    assert_equal 0, book.number_of_sales
    book.recalculate_sales_count!
    assert_nil book.reload.avg_score
    assert_equal 0, book.number_of_sales
  end

  test "enabled search invokes gem indexing with fresh statistics and review text" do
    result = scenario("search_statistics")
    assert result.fetch("enabled")
    snapshots = result.fetch("snapshots")
    assert_equal 6, snapshots.size
    assert_equal [ 5.0, 5.0, nil, nil, nil, nil ], snapshots.map { |item| item.fetch("avg_score") }
    assert_equal [ 0, 0, 0, 10, 20, 0 ], snapshots.map { |item| item.fetch("number_of_sales") }
    assert_equal [ "Initial text", "Updated text", "", "", "", "" ], snapshots.map { |item| item.fetch("review_text") }
    assert snapshots.all? { |item| item.fetch("fresh") }
    assert_equal 6, snapshots.map { |item| item.fetch("version") }.uniq.size
  end

  private

  def create_review(book, rating)
    book.reviews.create!(rating: rating, title: "Review", content: "Text", reviewer_name: "Reader")
  end

  def assert_one_invalidation
    previous = CacheGeneration.current_version.split(":")
    yield
    current = CacheGeneration.current_version.split(":")
    assert_equal previous.first, current.first
    assert_equal previous.last.to_i + 1, current.last.to_i
  end
end
