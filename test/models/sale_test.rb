require "test_helper"

class SaleTest < ActiveSupport::TestCase
  test "is valid with year, units_sold and revenue" do
    sale = Sale.new(year: 2020, units_sold: 100, revenue: 500.0)

    assert sale.valid?
  end

  test "rejects negative units_sold or revenue and missing year" do
    assert_not Sale.new(year: nil, units_sold: 1, revenue: 1.0).valid?
    assert_not Sale.new(year: 2020, units_sold: -1, revenue: 1.0).valid?
    assert_not Sale.new(year: 2020, units_sold: 1, revenue: -1.0).valid?
  end
end
