class SalesSeeder
  MIN_YEARS = 5
  MAX_YEARS = 10

  def self.call
    Book.each do |book|
      publication_year = book.publication_year || book.publication_date&.year
      raise "Book #{book.id} is missing a publication year" if publication_year.nil?

      sales = build_sales(publication_year)
      book.sales.destroy_all
      sales.each { |sale| book.sales.create!(sale) }
      book.update!(number_of_sales: sales.sum { |sale| sale[:units_sold] })
    end
  end

  def self.build_sales(publication_year)
    annual_sales = rand(MIN_YEARS..MAX_YEARS)
    units_sold = rand(3_000..12_000)
    base_price = rand(8.0..30.0)

    annual_sales.times.map do |offset|
      current_units = [ units_sold, 1 ].max
      price = (base_price * rand(0.9..1.1)).round(2)
      sale = {
        year: publication_year + offset,
        units_sold: current_units,
        revenue: (current_units * price).round(2)
      }

      # The random factor keeps individual curves distinct while the decay
      # preserves an overall downward sales trend.
      units_sold = (current_units * rand(0.65..0.85) * rand(0.9..1.1)).round
      sale
    end
  end
end
