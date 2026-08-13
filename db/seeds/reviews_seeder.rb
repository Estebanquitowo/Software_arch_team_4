class ReviewsSeeder
  def self.call
    Book.each do |book|
      rand(1..10).times do
        book.reviews.create!(
          rating: rand(1..5),
          title: Faker::Lorem.sentence(word_count: 4),
          content: Faker::Lorem.paragraph(sentence_count: 3),
          reviewer_name: Faker::Name.name
        )
      end
    end
  end
end
