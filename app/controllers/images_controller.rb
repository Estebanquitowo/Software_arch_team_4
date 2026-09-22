class ImagesController < ApplicationController
  def show
    relative = request.path.delete_prefix("/images/")

    unless ImageStorage.valid_relative?(relative)
      return head :not_found
    end

    file = ImageStorage.absolute(relative)
    return head :not_found unless File.exist?(file)

    send_file file, type: mime_type_for(relative), disposition: "inline"
  end

  private

  def mime_type_for(relative)
    ext = File.extname(relative)
    Rack::Mime.mime_type(ext, "application/octet-stream")
  end
end
