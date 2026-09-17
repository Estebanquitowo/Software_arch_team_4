module ApplicationHelper
  # Builds a stable URL for a stored image from its relative reference
  # (e.g. "books/<hex>.jpg" -> "/images/books/<hex>.jpg"). The path is what
  # both the app (no-proxy mode) and the reverse proxy (edge mode) serve.
  def stored_image_path(relative)
    return nil if relative.blank?

    "/images/#{relative}"
  end
end
