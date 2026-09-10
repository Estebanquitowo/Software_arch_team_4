# Run only through RegressionHelper#scenario, never against a user's database.
require "json"
require "stringio"
require_relative "network_faults"

name = ARGV.fetch(0)
database = ENV.fetch("REGRESSION_DATABASE")
raise "Unsafe database" unless database.match?(/\Aassignment3_regression_[0-9a-f]+_test\z/)
proxy = nil
search = nil
real_index_uid = nil
if name == "search_real"
  search = NetworkFaults::HTTPProxy.new(ENV.fetch("REGRESSION_MEILISEARCH_URL"))
  proxy = NetworkFaults::RedisProxy.new(ENV.fetch("REGRESSION_REDIS_URL"))
  ENV["SEARCH_ENABLED"] = "true"
  ENV["MEILISEARCH_URL"] = search.url
  ENV["CACHE_ENABLED"] = "true"
  ENV["REDIS_URL"] = proxy.url
elsif %w[redis_boot redis_invalidation reload average_redis].include?(name)
  proxy = NetworkFaults::RedisProxy.new(ENV.fetch("REGRESSION_REDIS_URL"), online: name != "redis_boot")
  ENV["CACHE_ENABLED"] = "true"
  ENV["REDIS_URL"] = proxy.url
elsif %w[search_write search_read search_statistics search_crud_outage search_task_failures search_coordination].include?(name)
  search = NetworkFaults::UnavailableSearch.new
  ENV["SEARCH_ENABLED"] = "true"
  ENV["MEILISEARCH_URL"] = search.url
end

begin
  require_relative "../../config/environment"
  require "action_dispatch/testing/integration"
  raise "Database isolation failed" unless Mongoid.default_client.database.name == database
  Rails.logger = ActiveSupport::Logger.new(StringIO.new)
  ActionController::Base.allow_forgery_protection = false
  Rails.application.env_config["action_dispatch.show_exceptions"] = :all

  if name == "search_real"
    Book.meilisearch_options[:index_uid] = database
    real_index_uid = Book.ms_index_uid
    raise "Unsafe test index" unless real_index_uid.start_with?("assignment3_regression_")
  end

  if proxy
    require "redis"
    # Only this namespace is inspected/removed. No FLUSHDB or shared keys.
    namespace = database
    Rails.cache.options[:namespace] = namespace
    observer = ActiveSupport::Cache::RedisCacheStore.new(url: ENV.fetch("REGRESSION_REDIS_URL"), namespace: namespace)
    observer.redis.then { |pool| pool.with(&:ping) }
  end

  require_relative "scenarios/cache_scenarios"
  require_relative "scenarios/search_scenarios"
  require_relative "scenarios/search_sync_scenarios"
  require_relative "scenarios/search_real_scenario"
  context = Object.new.extend(CacheScenarios).extend(SearchScenarios).extend(SearchSyncScenarios).extend(SearchRealScenario)
  result = context.public_send(name, proxy: proxy, observer: observer, search: search)
  puts "REGRESSION_RESULT=#{JSON.generate(result)}"
ensure
  begin
    if real_index_uid
      client = Meilisearch::Client.new(ENV.fetch("REGRESSION_MEILISEARCH_URL"))
      task = client.delete_index(real_index_uid).await
      unless task.status == "succeeded" || task.error&.fetch("code", nil) == "index_not_found"
        raise "Test index cleanup failed"
      end
    end
  ensure
    begin
      observer&.delete_matched("*")
      if defined?(Mongoid) && Mongoid.default_client.database.name == database
        Mongoid.default_client.database.drop
      end
    ensure
      proxy&.close
      search&.close
    end
  end
end
