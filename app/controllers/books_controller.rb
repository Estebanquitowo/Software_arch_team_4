class BooksController < ApplicationController
  PAGE_SIZE = 20
  before_action :set_book, only: %i[ show edit update destroy ]

  def index
    @page = [ Integer(params[:page] || 1, exception: false) || 1, 1 ].max
    cache_key = "books/index/page/#{@page}"
    result = CacheService.fetch(cache_key, expires_in: CacheService::CACHE_TTL[:books_index]) do
      total = Book.count
      books = Book.order_by(title: :asc).skip((@page - 1) * PAGE_SIZE).limit(PAGE_SIZE).to_a
      { total: total, books: books }
    end
    @total = result[:total]
    @total_pages = [ (@total / PAGE_SIZE.to_f).ceil, 1 ].max
    @books = result[:books]
  end

  # GET /books/1 or /books/1.json
  def show
  end

  # GET /books/new
  def new
    @book = Book.new
  end

  # GET /books/1/edit
  def edit
  end

  # POST /books or /books.json
  def create
    @book = Book.new(book_params)
    @book.cover_image_upload = uploaded_cover

    respond_to do |format|
      if @book.save
        store_cover
        format.html { redirect_to @book, notice: "Book was successfully created." }
        format.json { render :show, status: :created, location: @book }
      else
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @book.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /books/1 or /books/1.json
  def update
    @book.cover_image_upload = uploaded_cover

    respond_to do |format|
      if @book.update(book_params)
        replace_or_remove_cover
        format.html { redirect_to @book, notice: "Book was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @book }
      else
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @book.errors, status: :unprocessable_content }
      end
    end
  end

  # DELETE /books/1 or /books/1.json
  def destroy
    @book.destroy!

    respond_to do |format|
      format.html { redirect_to books_path, notice: "Book was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    def set_book
      @book = Book.find(params.expect(:id))
    end

    def book_params
      params.expect(book: [ :title, :summary, :publication_date, :publication_year, :author_id ])
    end

    def uploaded_cover
      params.dig(:book, :cover_image)
    end

    def remove_cover?
      ActiveModel::Type::Boolean.new.cast(params.dig(:book, :remove_cover_image))
    end

    # Stores the uploaded cover image and persists the new relative reference.
    # The image is only stored once validations have passed, so an invalid file
    # never leaves an orphan on disk.
    def store_cover
      upload = uploaded_cover
      return if upload.blank?

      relative = ImageStorage.store(upload, kind: "books")
      @book.set(cover_image: relative)
    end

    def replace_or_remove_cover
      return remove_cover if uploaded_cover.blank?

      new_relative = ImageStorage.store(uploaded_cover, kind: "books")
      old_relative = @book.cover_image
      @book.set(cover_image: new_relative)
      ImageStorage.delete(old_relative) if old_relative.present?
    end

    def remove_cover
      return unless remove_cover?

      old_relative = @book.cover_image
      @book.set(cover_image: nil)
      ImageStorage.delete(old_relative)
    end
end
