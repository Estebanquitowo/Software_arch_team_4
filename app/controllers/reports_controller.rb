class ReportsController < ApplicationController
  # GET /reports/authors_summary
  def authors_summary
    @sort_column = %w[name books_count avg_score total_sales].include?(params[:sort]) ? params[:sort] : "name"
    @sort_direction = params[:dir] == "desc" ? "desc" : "asc"
    @country_filter = params[:country].to_s.strip

    pipeline = build_authors_summary_pipeline
    @authors_summary = Author.collection.aggregate(pipeline).to_a

    @authors_summary.sort_by! { |a| a[@sort_column] || "" }
    @authors_summary.reverse! if @sort_direction == "desc"

    @countries = Author.distinct(:country_of_origin).compact.sort
  end

  # GET /reports/top_rated_books
  def top_rated_books
    @books = Book.where(:avg_score.ne => nil)
                 .order_by(avg_score: :desc)
                 .limit(10)
                 .to_a

    @book_details = @books.map do |book|
      reviews = book.reviews.to_a
      sorted = reviews.sort_by { |r| r.rating || 0 }
      {
        book: book,
        author_name: book.author&.name,
        highest_review: sorted.last,
        lowest_review: sorted.first
      }
    end
  end

  # GET /reports/top_selling_books
  def top_selling_books
    books = Book.order_by(number_of_sales: :desc).limit(50).to_a

    author_ids = books.map(&:author_id).uniq
    author_total_sales = compute_author_total_sales(author_ids)

    top5_by_year = compute_top5_by_year

    @selling_books = books.map do |book|
      author = book.author
      {
        book: book,
        author_name: author&.name,
        book_sales: book.number_of_sales,
        author_sales: author_total_sales[author&.id] || 0,
        top5_in_year: top5_by_year.dig(book.publication_year, book.id) || false
      }
    end
  end

  private

  def build_authors_summary_pipeline
    pipeline = []

    pipeline << { "$lookup" => { from: "books", localField: "_id", foreignField: "author_id", as: "books" } }

    pipeline << {
      "$addFields" => {
        "books_count" => { "$size" => "$books" },
        "avg_score" => { "$avg" => "$books.avg_score" },
        "total_sales" => { "$sum" => "$books.number_of_sales" }
      }
    }

    if @country_filter.present?
      pipeline << { "$match" => { "country_of_origin" => /#{@country_filter}/i } }
    end

    pipeline << { "$project" => { "books" => 0 } }

    pipeline
  end

  def compute_author_total_sales(author_ids)
    return {} if author_ids.empty?

    books_by_author = Book.where(:author_id.in => author_ids)
                          .group_by(&:author_id)

    books_by_author.transform_values do |books|
      books.sum { |b| b.number_of_sales || 0 }
    end
  end

  def compute_top5_by_year
    top5 = {}

    years = Book.distinct(:publication_year).compact
    years.each do |year|
      year_books = Book.where(publication_year: year).order_by(number_of_sales: :desc).limit(5).to_a
      top5[year] = year_books.each_with_object({}) { |b, h| h[b.id] = true }
    end

    top5
  end
end
