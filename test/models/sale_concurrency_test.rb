require_relative "../support/regression_helper"

class SaleConcurrencyTest < ActiveSupport::TestCase
  include RegressionHelper
  teardown { cleanup_regression_records }

  test "total includes both persisted sales from stale request instances" do
    book = regression_book
    first = Book.find(book.id)
    second = Book.find(book.id)
    # A reads []; B reads []; A writes 10; B writes 20 using its old snapshot.
    first.sales.to_a
    second.sales.to_a
    first.sales.create!(year: 2020, units_sold: 10)
    second.sales.create!(year: 2021, units_sold: 20)

    fresh = Book.find(book.id)
    assert_equal [ 10, 20 ], fresh.sales.map(&:units_sold).sort
    assert_equal 30, fresh.number_of_sales, "Both sales persisted, but the derived total used stale state"
  end
end
