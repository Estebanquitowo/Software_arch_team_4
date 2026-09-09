require_relative "../support/regression_helper"

class CacheInvalidationTest < ActionDispatch::IntegrationTest
  include RegressionHelper

  test "book cache returns fresh data after Rails reload and HTTP update" do
    result = scenario("reload")
    assert_equal "Original title", result["before"]
    assert_equal "Original title", result["cached_before"]
    assert_equal 303, result["write_status"]
    assert_equal "Updated title", result["database"]
    assert_equal result["database"], result["returned"], "Reload lost invalidation: #{result}"
  end

  test "invalidation during Redis outage cannot resurrect stale data on recovery" do
    result = scenario("redis_invalidation")
    assert_equal "Original title", result["cached_before"]
    assert_equal 303, result["write_status"]
    assert_equal "Updated title", result["database"]
    assert_equal result["database"], result["returned"], "MongoDB vs stranded Redis vs response: #{result}"
  end
end
