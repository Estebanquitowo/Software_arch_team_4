require "test_helper"

class StaticServeTest < ActiveSupport::TestCase
  setup do
    @original = ENV["SERVE_STATIC"]
  end

  teardown do
    ENV["SERVE_STATIC"] = @original
  end

  test "defaults to true when not configured" do
    ENV.delete("SERVE_STATIC")

    assert StaticServe.enabled?
  end

  test "enables static serving for explicit true" do
    ENV["SERVE_STATIC"] = "true"

    assert StaticServe.enabled?
  end

  test "disables static serving for false" do
    ENV["SERVE_STATIC"] = "false"

    assert_not StaticServe.enabled?
  end

  test "handles truthy and falsy shorthand" do
    ENV["SERVE_STATIC"] = "1"
    assert StaticServe.enabled?

    ENV["SERVE_STATIC"] = "0"
    assert_not StaticServe.enabled?
  end

  test "initializer applies the flag to the public file server" do
    # Boot-time wiring: with SERVE_STATIC unset the Rails app must serve
    # public/ assets (e.g. favicon, precompiled digest assets).
    assert Rails.application.config.public_file_server.enabled
  end
end
