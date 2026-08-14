require_relative "seeds/hardcover_seeder"
require_relative "seeds/author_details_seeder"
require_relative "seeds/reviews_seeder"
require_relative "seeds/sales_seeder"

HardcoverSeeder.call
AuthorDetailsSeeder.call
ReviewsSeeder.call
SalesSeeder.call
