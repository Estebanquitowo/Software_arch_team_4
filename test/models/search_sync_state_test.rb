require_relative "../support/regression_helper"

class SearchSyncStateTest < ActiveSupport::TestCase
  include RegressionHelper

  setup do
    @old_url = ENV["MEILISEARCH_URL"]
    ENV["MEILISEARCH_URL"] = "http://state-#{SecureRandom.hex(8)}.invalid"
    @state_id = SearchSyncState.state_id
  end

  teardown do
    cleanup_regression_records
    SearchSyncState.collection.find(_id: @state_id).delete_one
    ENV["MEILISEARCH_URL"] = @old_url
  end

  test "initial state is dirty and concurrent increments do not lose revisions" do
    assert SearchSyncState.current.fetch("dirty")
    threads = 8.times.map { Thread.new { SearchSyncState.mark_dirty! } }
    revisions = threads.map(&:value).map { |state| state.fetch("revision") }
    assert_equal (1..8).to_a, revisions.sort
    assert_equal 8, SearchSyncState.current.fetch("revision")
  end

  test "only one owner acquires and releases coordination" do
    assert SearchSyncState.acquire("first")
    assert_nil SearchSyncState.acquire("second")
    assert_not SearchSyncState.release("second")
    assert_equal "first", SearchSyncState.current.fetch("lock_token")
    assert SearchSyncState.release("first")
    assert SearchSyncState.acquire("second")
  end

  test "a concurrent change prevents clean publication and wrong owners cannot publish" do
    acquired = SearchSyncState.acquire("owner")
    assert_nil SearchSyncState.publish_clean("other", acquired.fetch("revision"))
    change = SearchSyncState.mark_dirty!
    assert_nil SearchSyncState.publish_clean("owner", acquired.fetch("revision"))
    assert SearchSyncState.current.fetch("dirty")
    clean = SearchSyncState.publish_clean("owner", change.fetch("revision"))
    assert_not clean.fetch("dirty")
    assert_equal change.fetch("revision") + 1, clean.fetch("revision")
  end

  test "disabled search records changes without trying a nonexistent server" do
    assert_not SearchService.enabled?
    book = regression_book
    before = SearchSyncState.current.fetch("revision")
    book.update!(title: "Disabled search update")
    assert_equal before + 1, SearchSyncState.current.fetch("revision")
    assert SearchSyncState.current.fetch("dirty")
    assert_nil SearchSyncState.current.fetch("lock_token")
    assert_equal :disabled, SearchSyncService.reconcile!
  end

  test "administrative unlock requires the exact token and preserves recovery debt" do
    state = SearchSyncState.acquire("owner")
    assert_raises(ArgumentError) { SearchSyncState.unlock_abandoned!("") }
    assert_not SearchSyncState.unlock_abandoned!("wrong")
    assert SearchSyncState.unlock_abandoned!("owner")
    current = SearchSyncState.current
    assert current.fetch("dirty")
    assert_nil current.fetch("lock_token")
    assert_equal state.fetch("revision") + 1, current.fetch("revision")
  end
end
