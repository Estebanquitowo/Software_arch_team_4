class AuthorsController < ApplicationController
  PAGE_SIZE = 20
  before_action :set_author, only: %i[ show edit update destroy ]

  # GET /authors or /authors.json
  def index
    @page = [ Integer(params[:page] || 1, exception: false) || 1, 1 ].max
    @total = Author.count
    @total_pages = [ (@total / PAGE_SIZE.to_f).ceil, 1 ].max

    @authors = Author.order_by(title: :asc).skip((@page - 1) * PAGE_SIZE).limit(PAGE_SIZE).to_a
  end

  # GET /authors/1 or /authors/1.json
  def show
  end

  # GET /authors/new
  def new
    @author = Author.new
  end

  # GET /authors/1/edit
  def edit
  end

  # POST /authors or /authors.json
  def create
    @author = Author.new(author_params)
    @author.image_upload = uploaded_image

    respond_to do |format|
      if @author.save
        store_image
        format.html { redirect_to @author, notice: "Author was successfully created." }
        format.json { render :show, status: :created, location: @author }
      else
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @author.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /authors/1 or /authors/1.json
  def update
    @author.image_upload = uploaded_image

    respond_to do |format|
      if @author.update(author_params)
        replace_or_remove_image
        format.html { redirect_to @author, notice: "Author was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @author }
      else
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @author.errors, status: :unprocessable_content }
      end
    end
  end

  # DELETE /authors/1 or /authors/1.json
  def destroy
    @author.destroy!

    respond_to do |format|
      format.html { redirect_to authors_path, notice: "Author was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_author
      @author = Author.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def author_params
      params.expect(author: [ :name, :date_of_birth, :country_of_origin, :short_description ])
    end

    def uploaded_image
      params.dig(:author, :image)
    end

    def remove_image?
      ActiveModel::Type::Boolean.new.cast(params.dig(:author, :remove_image))
    end

    def store_image
      upload = uploaded_image
      return if upload.blank?

      relative = ImageStorage.store(upload, kind: "authors")
      @author.set(image: relative)
    end

    def replace_or_remove_image
      return remove_image if uploaded_image.blank?

      new_relative = ImageStorage.store(uploaded_image, kind: "authors")
      old_relative = @author.image
      @author.set(image: new_relative)
      ImageStorage.delete(old_relative) if old_relative.present?
    end

    def remove_image
      return unless remove_image?

      old_relative = @author.image
      @author.set(image: nil)
      ImageStorage.delete(old_relative)
    end
end
