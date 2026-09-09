module CacheScenarios
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
