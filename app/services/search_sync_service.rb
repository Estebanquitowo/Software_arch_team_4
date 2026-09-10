require "meilisearch"

# The main write, dirty marker, remote tasks and clean publication are separate
# operations, not a distributed transaction. Only this service writes the index.
class SearchSyncService
  class TaskFailed < StandardError; end
  SEARCH_ERRORS = [ Meilisearch::ApiError, Meilisearch::CommunicationError,
                    Meilisearch::TimeoutError, TaskFailed ].freeze
  OPERATION_SECONDS = 15
  BATCH_SIZE = 100

  def self.book_changed(book_id)
    new.book_changed(book_id)
  end

  def self.book_deleted(book_id)
    # Read MongoDB again: a missing Book becomes a remote delete, never an upsert
    # reconstructed from the stale instance that triggered the callback.
    new.book_changed(book_id)
  end

  def self.reconcile!
    new.reconcile!
  end

  def self.clear!
    new.clear!
  end

  def self.search_failed!(error)
    SearchSyncState.mark_dirty!
    log_failure(error)
  end

  def self.log_failure(error)
    # SDK messages can contain credentials, URLs or document payloads.
    Rails.logger.warn("[SearchSync] #{error.class.name}; index remains dirty")
  end

  def self.remote
    yield
  rescue EOFError, SocketError, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH => error
    # SDK 0.32 does not wrap every socket failure. Normalize only transport
    # failures at SDK call sites, not MongoDB work or document serialization.
    raise Meilisearch::CommunicationError, error.class.name
  end

  def initialize(client: nil)
    @client = client
  end

  def book_changed(book_id)
    change = SearchSyncState.mark_dirty!
    return :disabled unless SearchService.enabled?

    with_lock do |token|
      ensure_index!
      book = Book.where(id: book_id).first
      book ? index_book(book) : verify_task! { index.delete_document(book_id.to_s) }
      if change.fetch("was_dirty") || SearchSyncState.current.fetch("revision") != change.fetch("revision")
        rebuild!(token) # At most one complete reconstruction for this event.
      else
        publish_clean(token, change.fetch("revision"))
      end
    end
  end

  def reconcile!
    SearchSyncState.mark_dirty!
    return :disabled unless SearchService.enabled?

    with_lock { |token| rebuild!(token) }
  end

  def clear!
    SearchSyncState.mark_dirty!
    return :disabled unless SearchService.enabled?

    with_lock do
      ensure_index!
      drain_pending_tasks!
      verify_task! { index.delete_all_documents }
      :cleared # An intentionally empty index is NOT reconciled with MongoDB.
    end
  end

  private

  def with_lock
    token = SecureRandom.uuid
    return :busy unless SearchSyncState.acquire(token)

    begin
      @deadline = monotonic_time + OPERATION_SECONDS
      yield token
    rescue *SEARCH_ERRORS => error
      self.class.log_failure(error)
      :unavailable
    ensure
      SearchSyncState.release(token)
    end
  end

  def client
    @client ||= Meilisearch::Rails.client
  end

  def index
    @index ||= client.index(Book.ms_index_uid)
  end

  def ensure_index!
    remaining_ms
    begin
      self.class.remote { index.fetch_info }
    rescue Meilisearch::ApiError => error
      raise unless error.code == "index_not_found"

      verify_task! { client.create_index(Book.ms_index_uid, primary_key: "id") }
    end
    settings = Book.meilisearch_settings.to_settings
    actual = self.class.remote { index.settings }
    unless settings.all? { |key, value| actual[key.to_s] == value }
      verify_task! { index.update_settings(settings) }
    end
  end

  def document_for(book)
    # Same DSL/ID representation as the current gem integration; no second
    # definition of title, summary, author_name or embedded review_text.
    Book.meilisearch_settings.get_attributes(book).merge("id" => book.id.to_s)
  end

  def index_book(book)
    document = document_for(book)
    verify_task! { index.add_documents([ document ]) }
  end

  def rebuild!(token)
    revision = SearchSyncState.current.fetch("revision")
    ensure_index!
    # A timed-out request may have left an accepted task on the server. Settle
    # previous work before clearing, without a periodic recovery/ping loop.
    drain_pending_tasks!
    verify_task! { index.delete_all_documents }
    Book.all.each_slice(BATCH_SIZE) do |books|
      remaining_ms
      documents = books.map { |book| document_for(book) }
      verify_task! { index.add_documents(documents) }
    end
    publish_clean(token, revision)
  end

  def drain_pending_tasks!
    loop do
      remaining_ms
      tasks = self.class.remote do
        client.tasks(index_uids: [ Book.ms_index_uid ], statuses: %w[enqueued processing], limit: BATCH_SIZE).fetch("results")
      end
      break if tasks.empty?

      tasks.each { |task| self.class.remote { client.wait_for_task(task.fetch("uid"), remaining_ms, 50) } }
    end
  end

  def verify_task!
    remaining_ms
    task = self.class.remote { yield }
    result = self.class.remote { task.await(remaining_ms, 50) }
    raise TaskFailed, "Search task did not succeed" unless result.status == "succeeded"

    result
  end

  def publish_clean(token, revision)
    SearchSyncState.publish_clean(token, revision) ? :clean : :dirty
  end

  def remaining_ms
    remaining = ((@deadline - monotonic_time) * 1000).to_i
    raise Meilisearch::TimeoutError if remaining <= 0

    remaining
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
