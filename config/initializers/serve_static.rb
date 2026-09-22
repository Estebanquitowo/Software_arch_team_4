# When SERVE_STATIC=false the application stops serving files from public/
# (Propshaft/asset pipeline output, favicon, robots.txt, etc.) and uploaded
# images via ImagesController.  An upstream reverse proxy (HAProxy) is then
# expected to intercept those paths, fetch them from a backend on the first
# request, and cache them for subsequent clients.
#
# Default: true (the app serves everything — safe without a proxy).
Rails.application.config.after_initialize do
  Rails.application.config.public_file_server.enabled = StaticServe.enabled?
end
