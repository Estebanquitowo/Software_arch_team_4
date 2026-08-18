class SalesController < ApplicationController
  before_action :set_book
  before_action :set_sale, only: %i[ show edit update destroy ]

  # GET /books/:book_id/sales
  def index
    @sales = @book.sales
  end

  # GET /books/:book_id/sales/:id
  def show
  end

  # GET /books/:book_id/sales/new
  def new
    @sale = @book.sales.build
  end

  # GET /books/:book_id/sales/:id/edit
  def edit
  end

  # POST /books/:book_id/sales
  def create
    @sale = @book.sales.build(sale_params)

    if @sale.save
      redirect_to [ @book, @sale ], notice: "Sale record was successfully added."
    else
      render :new, status: :unprocessable_content
    end
  end

  # PATCH/PUT /books/:book_id/sales/:id
  def update
    if @sale.update(sale_params)
      redirect_to [ @book, @sale ], notice: "Sale record was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  # DELETE /books/:book_id/sales/:id
  def destroy
    @sale.destroy!
    redirect_to @book, notice: "Sale record was successfully deleted.", status: :see_other
  end

  private

  def set_book
    @book = Book.find(params[:book_id])
  end

  def set_sale
    @sale = @book.sales.find(params[:id])
  end

  def sale_params
    params.expect(sale: [ :year, :units_sold, :revenue ])
  end
end
