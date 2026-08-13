require "date"
require "set"

class HardcoverSeeder
  TARGET_AUTHORS = 50
  TARGET_BOOKS = 300
  PAGE_SIZE = 100
  MAX_PAGES = 50
  PLACEHOLDER_AUTHOR_NAMES = [ "unknown" ].freeze

  def self.call
    candidates = {}
    selected_authors = []
    selected_books = []
    client = HardcoverClient.new

    MAX_PAGES.times do |page_index|
      page_number = page_index + 1
      puts "Fetching Hardcover page #{page_number}..."

      contributions = client.query(query, variables: { offset: page_index * PAGE_SIZE }).fetch("contributions", [])
      break if contributions.empty?

      add_candidates(candidates, contributions)
      selected_authors = select_authors(candidates.values)
      selected_books = selected_books(selected_authors)
      log_progress(selected_authors, selected_books)

      break if targets_met?(selected_authors, selected_books)
      break if contributions.size < PAGE_SIZE
    end

    ensure_targets!(selected_authors, selected_books)
    Book.delete_all
    Author.delete_all
    create_records(selected_authors, selected_books)
  end

  def self.query
    <<~GRAPHQL
      query HardcoverContributions($offset: Int!) {
        contributions(
          limit: #{PAGE_SIZE}
          offset: $offset
          where: {
            contribution: { _eq: "Author" }
            author: { name: { _neq: "Unknown" } }
          }
        ) {
          contribution
          author {
            id
            name
            born_date
            location
            bio
          }
          book {
            id
            title
            description
          }
        }
      }
    GRAPHQL
  end

  def self.add_candidates(candidates, contributions)
    contributions.each do |contribution|
      next unless contribution["contribution"] == "Author"

      author = valid_author(contribution["author"])
      book = valid_book(contribution["book"])
      next unless author && book

      candidate = candidates[author[:source_id]] ||= author.merge(books: {})
      candidate[:books][book[:id]] ||= book.merge(author_id: author[:source_id])
    end
  end

  def self.select_authors(candidates)
    selected = []
    selected_book_ids = Set.new

    candidates.sort_by { |candidate| [ -candidate[:books].size, candidate[:source_id] ] }.each do |candidate|
      break if selected.size == TARGET_AUTHORS

      new_books = candidate[:books].values.reject { |book| selected_book_ids.include?(book[:id]) }
      next if new_books.empty?

      selected << candidate.merge(books: new_books)
      new_books.each { |book| selected_book_ids << book[:id] }
    end

    selected
  end

  def self.selected_books(authors)
    selected_ids = Set.new
    books = authors.filter_map do |author|
      book = author[:books].first
      selected_ids << book[:id]
      book
    end

    authors.flat_map { |author| author[:books] }.each do |book|
      break if books.size == TARGET_BOOKS
      next if selected_ids.include?(book[:id])

      selected_ids << book[:id]
      books << book
    end

    books
  end

  def self.ensure_targets!(authors, books)
    return if targets_met?(authors, books)

    raise "Hardcover did not return enough valid data (authors: #{authors.size}/#{TARGET_AUTHORS}, books: #{books.size}/#{TARGET_BOOKS})"
  end

  def self.targets_met?(authors, books)
    authors.size >= TARGET_AUTHORS && books.size >= TARGET_BOOKS
  end

  def self.log_progress(authors, books)
    puts "Valid authors: #{authors.size}/#{TARGET_AUTHORS}"
    puts "Valid books: #{books.size}/#{TARGET_BOOKS}"
  end

  def self.create_records(authors, books)
    books_by_author = books.group_by { |book| book[:author_id] }

    authors.each do |author_data|
      author = Author.create!(author_data.except(:books, :source_id))
      books_by_author.fetch(author_data[:source_id], []).each do |book_data|
        Book.create!(
          title: book_data[:title],
          summary: book_data[:summary],
          author: author
        )
      end
    end
  end

  def self.valid_author(author_data)
    source_id = text(author_data&.fetch("id", nil))
    name = text(author_data&.fetch("name", nil))
    return if source_id.nil? || name.nil? || placeholder_author_name?(name)

    {
      source_id: source_id,
      name: name,
      date_of_birth: parse_date(author_data["born_date"]),
      country_of_origin: text(author_data["location"]),
      short_description: text(author_data["bio"])
    }
  end

  def self.valid_book(book_data)
    id = text(book_data&.fetch("id", nil))
    title = text(book_data&.fetch("title", nil))
    summary = text(book_data&.fetch("description", nil))
    return if id.nil? || title.nil? || summary.nil?

    { id: id, title: title, summary: summary }
  end

  def self.text(value)
    value.to_s.strip.presence
  end

  def self.placeholder_author_name?(name)
    PLACEHOLDER_AUTHOR_NAMES.include?(name.downcase)
  end

  def self.parse_date(value)
    Date.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end
end
