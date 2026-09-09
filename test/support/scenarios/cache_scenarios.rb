module CacheScenarios
  def average_redis(proxy:, observer:, **)
    previous_logger = Rails.logger
    logs = StringIO.new
    Rails.logger = ActiveSupport::Logger.new(logs)
    book = fixture_book
    key = "books/#{book.id}/average_review_score"
    # Exercise the actual book detail view, not only an otherwise unused API.
    session.get("/books/#{book.id}")
    page_status = session.response.status
    nil_cached = observer.exist?(key, version: CacheGeneration.current_version) && observer.read(key).nil?
    hits = []
    on_hit = ->(*args) { hits << ActiveSupport::Notifications::Event.new(*args).payload }
    ActiveSupport::Notifications.subscribed(on_hit, "cache_fetch_hit.active_support") { book.average_review_score }
    nil_hits = hits.count { |event| event[:key] == key }

    review = book.reviews.create!(rating: 5, title: "A", content: "A", reviewer_name: "A")
    purged_create = !observer.exist?(key)
    warm = book.average_review_score
    old_version = CacheGeneration.current_version
    proxy.offline!
    session.patch("/books/#{book.id}/reviews/#{review.id}", params: { review: { rating: 1 } })
    write_status = session.response.status
    generation_advanced = old_version != CacheGeneration.current_version
    purge_warning = logs.string.include?("[Cache] Redis delete_entry failed (")
    offline = book.average_review_score
    stranded = observer.read(key, version: old_version)
    proxy.online!
    recovered = book.average_review_score
    redis_value = observer.read(key, version: CacheGeneration.current_version)
    hits.clear
    second_read = nil
    ActiveSupport::Notifications.subscribed(on_hit, "cache_fetch_hit.active_support") { second_read = book.average_review_score }
    recovered_hits = hits.count { |event| event[:key] == key }
    # Text-only updates must purge too, although the average remains unchanged.
    Book.find(book.id).reviews.find(review.id).update!(content: "Edited text")
    purged_update = !observer.exist?(key)
    updated_average = book.average_review_score
    Book.find(book.id).reviews.find(review.id).destroy!
    purged_destroy = !observer.exist?(key)
    empty_average = book.average_review_score
    { nil_cached: nil_cached, nil_hits: nil_hits, warm: warm, offline: offline, stranded: stranded,
      recovered: recovered, redis_value: redis_value, second_read: second_read,
      recovered_hits: recovered_hits, page_status: page_status, write_status: write_status,
      generation_advanced: generation_advanced, purge_warning: purge_warning,
      purged_create: purged_create, purged_update: purged_update, purged_destroy: purged_destroy,
      updated_average: updated_average, empty_average: empty_average,
      empty_cached: observer.exist?(key, version: CacheGeneration.current_version) }
  ensure
    Rails.logger = previous_logger
  end

  def session
    @session ||= ActionDispatch::Integration::Session.new(Rails.application).tap { |s| s.host! "localhost" }
  end

  def fixture_book
    author = Author.create!(name: "Regression author")
    Book.create!(author: author, title: "Original title", summary: "Regression summary")
  end

  def listed_title(id)
    session.get("/books")
    raise "List request failed: #{session.response.status}" unless session.response.status == 200
    controller = session.request.env["action_controller.instance"]
    controller.instance_variable_get(:@books).find { |b| b.id == id }.title
  end

  def cached_title(store, id)
    store.read("books/index/page/1")&.fetch(:books)&.find { |b| b.id == id }&.title
  end

  def disabled(**)
    executions = 0
    values = 2.times.map { CacheService.fetch("regression/disabled") { executions += 1 } }
    { enabled: CacheService.enabled?, values: values, executions: executions,
      retained: Rails.cache.exist?("regression/disabled"), store: Rails.cache.class.name }
  end

  def reload(**)
    book = fixture_book
    old = listed_title(book.id)
    cached_before = cached_title(Rails.cache, book.id)
    Rails.application.reloader.reload!
    ActionController::Base.allow_forgery_protection = false
    session.patch("/books/#{book.id}", params: { book: { title: "Updated title" } })
    status = session.response.status
    { before: old, cached_before: cached_before, write_status: status,
      database: Book.find(book.id).title, returned: listed_title(book.id) }
  end

  def redis_boot(proxy:, observer:, **)
    book = fixture_book
    before = listed_title(book.id)
    proxy.online!
    # A fresh key avoids mistaking a valid pre-outage memory hit for recovery.
    value = CacheService.fetch("regression/recovered") { Book.find(book.id).title }
    { before: before, value: value, redis_value: observer.read("regression/recovered"), store: Rails.cache.class.name }
  end

  def redis_invalidation(proxy:, observer:, **)
    book = fixture_book
    listed_title(book.id)
    old = cached_title(observer, book.id)
    proxy.offline!
    session.patch("/books/#{book.id}", params: { book: { title: "Updated title" } })
    status = session.response.status
    database = Book.find(book.id).title
    # Direct observer bypasses only the test's network fault, not app logic.
    stranded = cached_title(observer, book.id)
    proxy.online!
    { cached_before: old, stranded_redis: stranded, write_status: status,
      database: database, returned: listed_title(book.id) }
  end
end
