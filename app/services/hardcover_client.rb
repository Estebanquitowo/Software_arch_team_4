require "json"
require "net/http"
require "uri"

class HardcoverClient
  ENDPOINT = URI("https://api.hardcover.app/v1/graphql")

  class ConfigurationError < StandardError; end
  class RequestError < StandardError; end

  def initialize(token: ENV["HARDCOVER_API_TOKEN"])
    @token = token
  end

  def query(document, variables: {})
    raise ConfigurationError, "HARDCOVER_API_TOKEN must be set before importing Hardcover data" if @token.blank?

    request = Net::HTTP::Post.new(ENDPOINT)
    request["Authorization"] = "Bearer #{@token}"
    request["Content-Type"] = "application/json"
    request["Accept"] = "application/json"
    request.body = { query: document, variables: variables }.to_json

    response = Net::HTTP.start(
      ENDPOINT.host,
      ENDPOINT.port,
      use_ssl: true,
      open_timeout: 10,
      read_timeout: 30
    ) { |http| http.request(request) }

    body = parse_response(response)
    errors = body["errors"]
    raise RequestError, graphql_error_message(errors) if errors.present?

    body.fetch("data")
  rescue JSON::ParserError => e
    raise RequestError, "Hardcover returned invalid JSON: #{e.message}"
  end

  private

  def parse_response(response)
    unless response.is_a?(Net::HTTPSuccess)
      raise RequestError, "Hardcover request failed with HTTP #{response.code}: #{response.body}"
    end

    JSON.parse(response.body)
  end

  def graphql_error_message(errors)
    messages = errors.filter_map { |error| error["message"] if error.is_a?(Hash) }
    "Hardcover GraphQL error: #{messages.presence || errors.inspect}"
  end
end
