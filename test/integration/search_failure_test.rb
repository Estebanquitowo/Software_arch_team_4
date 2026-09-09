require_relative "../support/regression_helper"

class SearchFailureTest < ActionDispatch::IntegrationTest
  include RegressionHelper

  test "search outage cannot turn a persisted HTTP update into a server error" do
    result = scenario("search_write")
    assert result["enabled"]
    assert_operator result["requests"], :>, 0, "Real SDK must attempt HTTP, not silently disable search"
    assert_equal "Updated title", result["database"]
    assert_equal 303, result["status"], "Successful HTML CRUD must redirect despite optional search failure: #{result}"
  end

  test "search outage falls back to MongoDB summary search over HTTP" do
    result = scenario("search_read")
    assert result["enabled"]
    assert_operator result["requests"], :>, 0
    assert_equal 200, result["status"]
    assert_equal "meilisearch_error", result["engine"]
    assert_equal [ result["expected_id"] ], result["ids"]
  end
end
