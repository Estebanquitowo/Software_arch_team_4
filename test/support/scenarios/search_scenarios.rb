module SearchScenarios
  # Inspect the centralized delivery boundary after replacing the gem's auto
  # callbacks. Expectations on fresh statistics/text remain unchanged.
  def search_statistics(**)
    book = search_fixture
    clean_search_fixture
    require_relative "../search_double"
    original_index = SearchSyncService.instance_method(:index_book)
    snapshots = []
    SearchSyncService.define_method(:index_book) do |record|
      snapshots << {
        avg_score: record.avg_score, number_of_sales: record.number_of_sales,
        review_text: record.reviews.map(&:content).join(" "),
        fresh: !record.equal?(book), version: CacheGeneration.current_version
      }
      original_index.bind_call(self, record)
    end
    with_search_client(SearchDouble.new) do
      review = book.reviews.create!(rating: 5, title: "Review", content: "Initial text", reviewer_name: "Reader")
      review.update!(content: "Updated text")
      review.destroy!
      sale = book.sales.create!(year: 2020, units_sold: 10)
      sale.update!(units_sold: 20)
      sale.destroy!
    end
    { enabled: !!SearchService.enabled?, snapshots: snapshots }
  ensure
    SearchSyncService.define_method(:index_book, original_index) if original_index
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
    # This existing regression tests an outage discovered while previously
    # clean. Missing-state/dirty searches have their own no-HTTP coverage.
    clean_search_fixture
    session.get("/search", params: { q: "summaryonlyregressiontoken" })
    controller = session.request.env["action_controller.instance"]
    { enabled: !!SearchService.enabled?, requests: search.requests.size,
      status: session.response.status, engine: controller.instance_variable_get(:@engine),
      ids: controller.instance_variable_get(:@books).map { |b| b.id.to_s }, expected_id: book.id.to_s }
  end

  def clean_search_fixture
    token = SecureRandom.uuid
    state = SearchSyncState.acquire(token)
    raise "Fixture lock unavailable" unless state

    SearchSyncState.publish_clean(token, state.fetch("revision"))
    SearchSyncState.release(token)
  end

  def with_search_client(client)
    original_new = SearchSyncService.method(:new)
    SearchSyncService.define_singleton_method(:new) { original_new.call(client: client) }
    yield
  ensure
    SearchSyncService.define_singleton_method(:new, original_new)
  end
end
