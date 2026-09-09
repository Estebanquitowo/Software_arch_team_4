module SearchScenarios
  # Keep the gem's real instance ms_index! method, spying only on its class-level
  # delivery boundary. This verifies callback wiring, not server availability.
  # A subprocess isolates the enabled-at-boot model and the temporary spy.
  def search_statistics(**)
    book = search_fixture
    original_index = Book.method(:ms_index!)
    snapshots = []
    Book.define_singleton_method(:ms_index!) do |record, *_args|
      snapshots << {
        avg_score: record.avg_score, number_of_sales: record.number_of_sales,
        review_text: record.reviews.map(&:content).join(" "),
        fresh: !record.equal?(book), version: CacheGeneration.current_version
      }
    end
    review = book.reviews.create!(rating: 5, title: "Review", content: "Initial text", reviewer_name: "Reader")
    review.update!(content: "Updated text")
    review.destroy!
    sale = book.sales.create!(year: 2020, units_sold: 10)
    sale.update!(units_sold: 20)
    sale.destroy!
    { enabled: !!SearchService.enabled?, snapshots: snapshots }
  ensure
    Book.define_singleton_method(:ms_index!, original_index) if original_index
  end

  def search_fixture
    author = Author.create!(name: "Regression author")
    # Existing valid MongoDB data, inserted without requiring an available index.
    # The operation under test below DOES use the real HTTP controller/callbacks.
    book = Book.new(author: author, title: "Original title", summary: "summaryonlyregressiontoken")
    raise "Invalid fixture" unless book.valid?
    Book.collection.insert_one(book.attributes)
    Book.find(book.id)
  end

  def search_write(search:, **)
    book = search_fixture
    enabled = !!SearchService.enabled?
    session.patch("/books/#{book.id}", params: { book: { title: "Updated title" } })
    { enabled: enabled, requests: search.requests.size, status: session.response.status,
      database: Book.find(book.id).title }
  end

  def search_read(search:, **)
    book = search_fixture
    session.get("/search", params: { q: "summaryonlyregressiontoken" })
    controller = session.request.env["action_controller.instance"]
    { enabled: !!SearchService.enabled?, requests: search.requests.size,
      status: session.response.status, engine: controller.instance_variable_get(:@engine),
      ids: controller.instance_variable_get(:@books).map { |b| b.id.to_s }, expected_id: book.id.to_s }
  end
end
