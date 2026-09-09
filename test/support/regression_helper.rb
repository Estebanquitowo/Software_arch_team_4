require "test_helper"
require "json"
require "open3"
require "securerandom"

module RegressionHelper
  def regression_book
    raise "Regression tests require a test database" unless Rails.env.test? && Mongoid.default_client.database.name.end_with?("_test")

    author = Author.create!(name: "Regression #{SecureRandom.hex(6)}")
    book = Book.create!(author: author, title: "Original title", summary: "Regression summary")
    (@regression_records ||= []) << [ book.id, author.id ]
    book
  end

  def cleanup_regression_records
    (@regression_records || []).each do |book_id, author_id|
      Book.where(id: book_id).delete_all
      Author.where(id: author_id).delete_all
    end
  end

  # A new OS process is essential: development reloading and boot-time ENV must
  # not mutate the parent suite's models, callbacks, environment, or cache store.
  def scenario(name)
    database = "assignment3_regression_#{SecureRandom.hex(8)}_test"
    env = {
      "RAILS_ENV" => "development", "CACHE_ENABLED" => "false",
      "SEARCH_ENABLED" => "false", "REDIS_URL" => "", "CACHE_URL" => "",
      "MEILISEARCH_URL" => "", "SEARCH_URL" => "", "MEILISEARCH_API_KEY" => "",
      "MEILI_MASTER_KEY" => "", "HARDCOVER_API_TOKEN" => "",
      "REGRESSION_DATABASE" => database
    }
    # Preserve URI authentication/options while changing only the database.
    uri = ENV.fetch("MONGODB_TEST_URI", "mongodb://127.0.0.1:27017/software_arch_team4_test")
    env["MONGODB_URI"] = uri.sub(%r{(mongodb(?:\+srv)?://[^/]+)(?:/[^?]*)?}, "\\1/#{database}")
    output, errors, status = capture_scenario(env, name)
    assert status.success?, "Scenario #{name} failed before assertions:\n#{output}\n#{errors}"
    line = output.lines.find { |item| item.start_with?("REGRESSION_RESULT=") }
    assert line, "Scenario #{name} produced no evidence: #{output}\n#{errors}"
    JSON.parse(line.delete_prefix("REGRESSION_RESULT="))
  end

  def capture_scenario(env, name)
    Open3.popen3(env, RbConfig.ruby, Rails.root.join("test/support/scenario_runner.rb").to_s, name) do |input, output, errors, process|
      input.close
      stdout = Thread.new { output.read }
      stderr = Thread.new { errors.read }
      begin
        raise "Scenario #{name} exceeded 60 seconds (harness/backend timeout)" unless process.join(60)
        [ stdout.value, stderr.value, process.value ]
      ensure
        if process.alive?
          Process.kill("TERM", process.pid)
          Process.kill("KILL", process.pid) unless process.join(5)
          process.join
        end
        stdout.join
        stderr.join
      end
    end
  end
end
