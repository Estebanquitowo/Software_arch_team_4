require_relative "../support/regression_helper"

class SearchSyncServiceTest < ActiveSupport::TestCase
  include RegressionHelper

  test "CRUD survives search outage while persisting changes and dirty state" do
    result = scenario("search_crud_outage")
    assert_equal [ 302, 303, 302, 303, 303, 303 ], result.fetch("statuses")
    assert_equal [ true ] * 6, result.fetch("dirty")
    assert_equal [ true ] * 6, result.fetch("mongo_correct")
    assert_equal 6, result.fetch("revisions").uniq.size
    assert_nil result.fetch("lock")
    assert_operator result.fetch("requests"), :>=, 6
    assert_equal "mongo", result.fetch("dirty_engine")
    assert result.fetch("search_without_http")
  end

  test "failed tasks at every reconstruction stage leave debt and release the lock" do
    result = scenario("search_task_failures")
    assert_equal %w[unavailable unavailable unavailable], result.fetch("results")
    assert_equal [ true ] * 3, result.fetch("dirty")
    assert_equal [ nil ] * 3, result.fetch("locks")
    assert_equal %w[ArgumentError Mongo::Error::OperationFailure], result.fetch("propagated")
  end

  test "reconciliation excludes a competing owner and cannot clean a newer revision" do
    result = scenario("search_coordination")
    assert_equal "busy", result.fetch("competitor")
    assert_equal "dirty", result.fetch("first")
    assert_equal 1, result.fetch("clear_count")
    assert result.fetch("concurrent_change_saved")
    assert result.fetch("dirty")
    assert_nil result.fetch("lock")
    assert_equal "clean", result.fetch("retry")
    assert_not result.fetch("dirty_after_retry")
  end
end
