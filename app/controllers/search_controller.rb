class SearchController < ApplicationController
  PAGE_SIZE = 20

  # GET /search
  def index
    @query = params[:q].to_s.strip
    @page = [ Integer(params[:page] || 1, exception: false) || 1, 1 ].max

    if @query.present?
      words = @query.split(/\s+/).map { |w| Regexp.escape(w) }
      regex = Regexp.new(words.join("|"), Regexp::IGNORECASE)

      @total = Book.where(summary: regex).count
      @books = Book.where(summary: regex)
                   .order_by(title: :asc)
                   .skip((@page - 1) * PAGE_SIZE)
                   .limit(PAGE_SIZE)
                   .to_a
    else
      @total = 0
      @books = []
    end

    @total_pages = [ (@total / PAGE_SIZE.to_f).ceil, 1 ].max
  end
end
