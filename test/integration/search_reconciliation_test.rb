require_relative "../support/regression_helper"

class SearchReconciliationTest < ActionDispatch::IntegrationTest
  include RegressionHelper

  test "real Meilisearch reconciles outage deletes reviews pagination and search cache" do
    result = scenario("search_real")
    assert_equal "clean", result.fetch("initial")
    assert_equal "mongo", result.fetch("initial_engine")
    assert_equal [ "meilisearch" ] * 3, result.fetch("engines")
    assert result.fetch("field_matches")
    assert result.fetch("relevance")
    assert_equal [ 20, 2, 22 ], result.fetch("pages")
    assert result.fetch("disjoint_pages")
    assert result.fetch("old_cache_present"), result.inspect
    assert_equal "mongo", result.fetch("dirty_engine")
    assert_equal [ 303, 302 ], result.fetch("outage_statuses")
    assert result.fetch("dirty_after_outage")
    assert result.fetch("orphan_before_recovery")
    assert_empty result.fetch("dirty_deleted_ids")
    assert_equal 303, result.fetch("recovery_status")
    assert_not result.fetch("dirty_after_recovery")
    assert result.fetch("exact_ids")
    assert_not result.fetch("orphan_after_recovery")
    assert_equal "meilisearch", result.fetch("review_engine")
    assert result.fetch("review_indexed")
    assert result.fetch("edited_review_indexed")
    assert_empty result.fetch("deleted_review_ids")
    assert result.fetch("clear_task_dirty")
    assert_equal 0, result.fetch("clear_task_count")
    assert result.fetch("reindex_task_clean")
    assert_not result.fetch("empty_dirty")
    assert_equal 0, result.fetch("empty_count")
  end
end
