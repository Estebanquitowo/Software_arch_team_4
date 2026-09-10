class SearchController < ApplicationController
  PAGE_SIZE = 20

  def index
    @query = params[:q].to_s.strip
    @page = [ Integer(params[:page] || 1, exception: false) || 1, 1 ].max

    if @query.present?
      state = SearchSyncState.current
      result = if state.fetch("dirty")
        SearchService.mongo_search(@query, page: @page)
      else
        # Capture the state before cache access. Late writes retain the old key;
        # publishing clean increments revision, separating results after recovery.
        cache_key = "search/#{state.fetch('_id')}/#{state.fetch('epoch')}/#{state.fetch('revision')}/#{@query.parameterize}/page/#{@page}"
        CacheService.fetch(cache_key, expires_in: CacheService::CACHE_TTL[:search]) do
          SearchService.search(@query, page: @page)
        end
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
