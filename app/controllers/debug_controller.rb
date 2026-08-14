class DebugController < ApplicationController
  def show
    @authors = Author.all.order_by(name: :asc).to_a
    @books = Book.all.order_by(title: :asc).to_a
    @books_by_author_id = @books.group_by(&:author_id)
    @authors_by_id = @authors.index_by(&:id)
  end
end
