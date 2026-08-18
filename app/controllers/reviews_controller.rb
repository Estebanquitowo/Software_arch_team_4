class ReviewsController < ApplicationController
  before_action :set_book
  before_action :set_review, only: %i[ show edit update destroy ]

  # GET /books/:book_id/reviews
  def index
    @reviews = @book.reviews
  end

  # GET /books/:book_id/reviews/:id
  def show
  end

  # GET /books/:book_id/reviews/new
  def new
    @review = @book.reviews.build
  end

  # GET /books/:book_id/reviews/:id/edit
  def edit
  end

  # POST /books/:book_id/reviews
  def create
    @review = @book.reviews.build(review_params)

    respond_to do |format|
      if @review.save
        format.html { redirect_to [ @book, @review ], notice: "Review was successfully created." }
        format.json { render :show, status: :created, location: [ @book, @review ] }
      else
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @review.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /books/:book_id/reviews/:id
  def update
    respond_to do |format|
      if @review.update(review_params)
        format.html { redirect_to [ @book, @review ], notice: "Review was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: [ @book, @review ] }
      else
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @review.errors, status: :unprocessable_content }
      end
    end
  end

  # DELETE /books/:book_id/reviews/:id
  def destroy
    @review.destroy!

    respond_to do |format|
      format.html { redirect_to @book, notice: "Review was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    def set_book
      @book = Book.find(params[:book_id])
    end

    def set_review
      @review = @book.reviews.find(params[:id])
    end

    def review_params
      params.expect(review: [ :rating, :title, :content, :reviewer_name ])
    end
end
