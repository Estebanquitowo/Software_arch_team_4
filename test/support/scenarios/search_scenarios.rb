module SearchScenarios
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
