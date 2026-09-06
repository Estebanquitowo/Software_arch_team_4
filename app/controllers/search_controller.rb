class SearchController < ApplicationController
  PAGE_SIZE = 20

  def index
    @query = params[:q].to_s.strip
    @page = [ Integer(params[:page] || 1, exception: false) || 1, 1 ].max

    if @query.present?
      cache_key = "search/#{@query.parameterize}/page/#{@page}"
      result = CacheService.fetch(cache_key, expires_in: CacheService::CACHE_TTL[:search]) do
        SearchService.search(@query, page: @page)
      end
      @books = result[:books]
      @total = result[:total]
      @total_pages = result[:total_pages]
      @engine = result[:engine]
    else
      @total = 0
      @books = []
      @total_pages = 1
      @engine = :none
    end
  end
end
