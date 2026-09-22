# Decides whether this application instance serves static content itself.
#
# SERVE_STATIC=true  (default) — the app serves public/ assets and uploaded
#                                images normally (no reverse proxy in front).
# SERVE_STATIC=false — an upstream proxy (HAProxy) owns static assets at the
#                      edge and caches them; the app stops serving them.
class StaticServe
  def self.enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("SERVE_STATIC", "true"))
  end
end
