Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  root "home#index"

  resources :authors

  resources :books do
    resources :reviews, except: [ :show ]
  end

  get "reports/authors_summary", to: "reports#authors_summary"
  get "reports/top_rated_books", to: "reports#top_rated_books"
  get "reports/top_selling_books", to: "reports#top_selling_books"

  get "search", to: "search#index"

  get "debug", to: "debug#show"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
