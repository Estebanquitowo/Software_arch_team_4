require_relative "../search_double"

module SearchSyncScenarios
  def search_crud_outage(search:, **)
    author = Author.create!(name: "Outage author")
    statuses = []
    states = []
    correct = []
    record = ->(valid) do
      statuses << session.response.status
      states << SearchSyncState.current
      correct << valid
    end
    session.post("/books", params: { book: { title: "Outage book", summary: "Summary", author_id: author.id.to_s } })
    book = Book.find_by(title: "Outage book")
    record.call(book.persisted?)
    session.patch("/books/#{book.id}", params: { book: { title: "Updated book" } })
    record.call(book.reload.title == "Updated book")
    session.post("/books/#{book.id}/reviews", params: { review: { rating: 5, title: "Review", content: "Old text", reviewer_name: "Reader" } })
    review = book.reload.reviews.first
    record.call(book.avg_score == 5.0 && review.content == "Old text")
    session.patch("/books/#{book.id}/reviews/#{review.id}", params: { review: { rating: 1, content: "New text" } })
    record.call(book.reload.avg_score == 1.0 && book.reviews.first.content == "New text")
    session.delete("/books/#{book.id}/reviews/#{review.id}")
    record.call(book.reload.avg_score.nil? && book.reviews.empty?)
    session.delete("/books/#{book.id}")
    record.call(!Book.where(id: book.id).exists?)
    requests_before_search = search.requests.size
    dirty_search = SearchService.search("Outage")
    { statuses: statuses, dirty: states.map { |state| state.fetch("dirty") },
      revisions: states.map { |state| state.fetch("revision") }, mongo_correct: correct,
      lock: SearchSyncState.current.fetch("lock_token"), requests: search.requests.size,
      dirty_engine: dirty_search.fetch(:engine), search_without_http: search.requests.size == requests_before_search }
  end

  def search_task_failures(**)
    search_fixture
    results = []
    states = []
    %i[settings clear add].each do |stage|
      fake = SearchDouble.new
      fake.failure_stage = stage
      results << SearchSyncService.new(client: fake).reconcile!
      states << SearchSyncState.current
    end
    propagated = [ ArgumentError.new("Application error"), Mongo::Error::OperationFailure.new("Mongo error") ].map do |error|
      fake = SearchDouble.new
      fake.on_clear = -> { raise error }
      begin
        SearchSyncService.new(client: fake).reconcile!
        "not raised"
      rescue ArgumentError, Mongo::Error::OperationFailure => raised
        raise "Lock leaked" if SearchSyncState.current.fetch("lock_token")

        raised.class.name
      end
    end
    { results: results, dirty: states.map { |state| state.fetch("dirty") },
      locks: states.map { |state| state.fetch("lock_token") }, propagated: propagated }
  end

  def search_coordination(**)
    book = search_fixture
    fake = SearchDouble.new
    competitor = nil
    fake.on_clear = -> do
      book.update!(title: "Changed during reconciliation")
      competitor = SearchSyncService.new(client: fake).reconcile!
    end
    first = SearchSyncService.new(client: fake).reconcile!
    state = SearchSyncState.current
    count = fake.calls.count(:clear)
    fake.on_clear = nil
    retry_result = SearchSyncService.new(client: fake).reconcile!
    { competitor: competitor, first: first, dirty: state.fetch("dirty"),
      lock: state.fetch("lock_token"), clear_count: count, retry: retry_result,
      concurrent_change_saved: book.reload.title == "Changed during reconciliation",
      dirty_after_retry: SearchSyncState.current.fetch("dirty") }
  end
end
