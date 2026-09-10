module SearchRealScenario
  def search_real(search:, observer:, **)
    main = search_fixture
    # Valid isolated data inserted without callbacks for a first-activation/full
    # import test. Normal HTTP/controller writes below do execute all callbacks.
    main.set(title: "titleonlyprobe", summary: "summaryonlyprobe")
    Book.collection.find(_id: main.id).update_one("$set" => {
      "reviews" => [ { "_id" => BSON::ObjectId.new, "rating" => 5, "title" => "Review",
                       "content" => "reviewonlyprobe", "reviewer_name" => "Reader" } ], "avg_score" => 5.0
    })
    orphan = raw_search_book(main.author, "removedprobe", "Obsolete book")
    ranked = raw_search_book(main.author, "rankingprobe", "Other text")
    raw_search_book(main.author, "Different title", "rankingprobe")
    22.times { |i| raw_search_book(main.author, "galactic #{i}", "Pagination") }
    initial_engine = SearchService.search("summaryonlyprobe")[:engine]
    initial = SearchSyncService.reconcile!
    raise "Initial real reconciliation: #{initial}" unless initial == :clean
    matches = %w[titleonlyprobe summaryonlyprobe reviewonlyprobe].map { |query| SearchService.search(query) }
    first_page = SearchService.search("galactic", page: 1)
    second_page = SearchService.search("galactic", page: 2)
    relevance = SearchService.search("rankingprobe")[:books].first&.id == ranked.id

    cache_key = nil
    listener = ->(*args) do
      key = ActiveSupport::Notifications::Event.new(*args).payload.fetch(:key).to_s
      cache_key = key.delete_prefix("#{ENV.fetch('REGRESSION_DATABASE')}:")
    end
    ActiveSupport::Notifications.subscribed(listener, "cache_write.active_support") { http_search("removedprobe") }
    old_cache_present = cache_key && observer.exist?(cache_key)
    SearchSyncState.mark_dirty!
    dirty_engine = http_search("removedprobe")[:engine]

    search.offline!
    session.delete("/books/#{orphan.id}")
    deleted_status = session.response.status
    session.post("/books/#{main.id}/reviews", params: { review: {
      rating: 1, title: "Outage review", content: "outagereviewprobe", reviewer_name: "Reader"
    } })
    created_status = session.response.status
    dirty_after_outage = SearchSyncState.current.fetch("dirty")
    search.online!
    direct_index = Meilisearch::Client.new(ENV.fetch("REGRESSION_MEILISEARCH_URL")).index(Book.ms_index_uid)
    orphan_before = direct_index.get_document(orphan.id.to_s).fetch("id") == orphan.id.to_s
    dirty_deleted_ids = http_search("removedprobe")[:ids]
    session.patch("/books/#{main.id}", params: { book: { summary: "summaryonlyprobe recovered" } })
    recovery_status = session.response.status
    after_recovery = SearchSyncState.current
    ids = direct_index.documents(limit: 1000).fetch("results").map { |doc| doc.fetch("id") }
    review_search = http_search("outagereviewprobe")

    review = Book.find(main.id).reviews.find_by(content: "outagereviewprobe")
    review.update!(content: "editedreviewprobe")
    edited = SearchService.search("editedreviewprobe")[:books].map(&:id).include?(main.id)
    review.destroy!
    deleted_review_ids = SearchService.search("editedreviewprobe")[:books].map { |book| book.id.to_s }
    result = { initial: initial, initial_engine: initial_engine, engines: matches.map { |match| match[:engine] },
      field_matches: matches.all? { |match| match[:books].map(&:id) == [ main.id ] }, relevance: relevance,
      pages: [ first_page[:books].size, second_page[:books].size, first_page[:total] ],
      disjoint_pages: (first_page[:books].map(&:id) & second_page[:books].map(&:id)).empty?,
      old_cache_present: !!old_cache_present, dirty_engine: dirty_engine,
      outage_statuses: [ deleted_status, created_status ], dirty_after_outage: dirty_after_outage,
      orphan_before_recovery: orphan_before, dirty_deleted_ids: dirty_deleted_ids, recovery_status: recovery_status,
      dirty_after_recovery: after_recovery.fetch("dirty"), exact_ids: ids.sort == Book.pluck(:id).map(&:to_s).sort,
      orphan_after_recovery: ids.include?(orphan.id.to_s), review_engine: review_search[:engine],
      review_indexed: review_search[:ids] == [ main.id.to_s ], edited_review_indexed: edited,
      deleted_review_ids: deleted_review_ids }
    Rails.application.load_tasks
    Rake::Task["search:clear"].invoke
    result[:clear_task_dirty] = SearchSyncState.current.fetch("dirty")
    result[:clear_task_count] = direct_index.stats.fetch("numberOfDocuments")
    Rake::Task["search:reindex"].invoke # Alias must use the same reconciliation service.
    result[:reindex_task_clean] = !SearchSyncState.current.fetch("dirty")
    Book.delete_all # Guarded, random regression database only; tests empty rebuild.
    Rake::Task["search:reconcile"].reenable
    Rake::Task["search:reconcile"].invoke
    result.merge(empty_dirty: SearchSyncState.current.fetch("dirty"), empty_count: direct_index.stats.fetch("numberOfDocuments"))
  end

  def raw_search_book(author, title, summary)
    book = Book.new(author: author, title: title, summary: summary)
    raise "Invalid search fixture" unless book.valid?

    Book.collection.insert_one(book.attributes)
    book
  end

  def http_search(query)
    session.get("/search", params: { q: query })
    raise "Search HTTP #{session.response.status}" unless session.response.status == 200

    controller = session.request.env["action_controller.instance"]
    { engine: controller.instance_variable_get(:@engine), ids: controller.instance_variable_get(:@books).map { |book| book.id.to_s } }
  end
end
