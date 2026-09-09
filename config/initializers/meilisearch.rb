meili_url = ENV["MEILISEARCH_URL"].presence || ENV["SEARCH_URL"].presence
meili_key = ENV["MEILISEARCH_API_KEY"].presence || ENV["MEILI_MASTER_KEY"].presence
search_enabled = ENV.fetch("SEARCH_ENABLED", meili_url ? "true" : "false")

if meili_url && search_enabled == "true"
  begin
    require "meilisearch-rails"
    MeiliSearch::Rails.configuration = {
      meilisearch_url: meili_url,
      meilisearch_api_key: meili_key || "",
      per_environment: true
    }
    Rails.logger.info("[Search] Meilisearch enabled at #{meili_url}")
  rescue LoadError => e
    Rails.logger.warn("[Search] meilisearch-rails gem not installed (#{e.message}) -> Mongo fallback")
  end
else
  Rails.logger.info("[Search] Meilisearch disabled -> Mongo fallback (SEARCH_ENABLED=#{search_enabled}, URL=#{meili_url || 'nil'})")
end

module SearchService
  PAGE_SIZE = 20

  def self.enabled?
    ENV.fetch("SEARCH_ENABLED", "false") == "true" &&
      ENV["MEILISEARCH_URL"].present? &&
      defined?(MeiliSearch) &&
      Book.respond_to?(:ms_search)
  rescue StandardError
    false
  end

  def self.search(query, page: 1)
    query = query.to_s.strip
    return { books: [], total: 0, total_pages: 1, engine: :none } if query.blank?

    if enabled?
      meili_search(query, page: page)
    else
      mongo_search(query, page: page)
    end
  end

  def self.meili_search(query, page: 1)
    page = [ page.to_i, 1 ].max
    offset = (page - 1) * PAGE_SIZE
    result = Book.ms_search(query, limit: PAGE_SIZE, offset: offset)
    books = result.to_a
    total = result.raw_answer["estimatedTotalHits"] || result.raw_answer["totalHits"] || books.size
    total = total.to_i
    total = books.size if total == 0 && books.any?
    fallback_if_empty = total == 0
    if fallback_if_empty
      Rails.logger.warn("[Search] Meilisearch returned 0 hits, falling back to Mongo for query=#{query}")
      return mongo_search(query, page: page).merge(engine: :meilisearch_fallback)
    end
    total_pages = [ (total / PAGE_SIZE.to_f).ceil, 1 ].max
    { books: books, total: total, total_pages: total_pages, engine: :meilisearch }
  rescue StandardError => e
    Rails.logger.warn("[Search] Meilisearch failed (#{e.class}: #{e.message}), fallback to Mongo")
    mongo_search(query, page: page).merge(engine: :meilisearch_error)
  end

  def self.mongo_search(query, page: 1)
    page = [ page.to_i, 1 ].max
    words = query.split(/\s+/).map { |w| Regexp.escape(w) }
    regex = Regexp.new(words.join("|"), Regexp::IGNORECASE)
    criteria = Book.or({ title: regex }, { summary: regex },
                        { "reviews.title" => regex }, { "reviews.content" => regex })
    total = criteria.count
    books = criteria.order_by(title: :asc)
                    .skip((page - 1) * PAGE_SIZE)
                    .limit(PAGE_SIZE)
                    .to_a
    total_pages = [ (total / PAGE_SIZE.to_f).ceil, 1 ].max
    { books: books, total: total, total_pages: total_pages, engine: :mongo }
  end
end
