require_relative "../support/regression_helper"

class CacheServiceTest < ActiveSupport::TestCase
  include RegressionHelper

  test "explicitly disabled cache neither reports enabled nor retains fetch results" do
    result = scenario("disabled")
    assert_equal({ "enabled" => false, "values" => [ 1, 2 ], "executions" => 2, "retained" => false },
      result.except("store"), "CACHE_ENABLED=false must bypass cache, not just Redis: #{result}")
  end

  test "Redis recovers after boot outage without restarting Rails" do
    result = scenario("redis_boot")
    assert_equal "Original title", result["before"], "Mongo-backed read must survive the outage"
    assert_equal "Original title", result["value"]
    assert_equal "Original title", result["redis_value"], "Recovered Redis must receive new fetches without restarting: #{result}"
  end
end
