Rails.application.routes.draw do
  root "home#show"
  get "robots.txt", to: "home#robots", defaults: { format: :text }

  resource :session, only: %i[new create destroy]
  get "sign-in/:public_id", to: "sign_ins#show", as: :sign_in
  post "sign-in/:public_id", to: "sign_ins#create", as: :consume_sign_in

  resources :files, only: %i[index create show destroy] do
    get :download, on: :member
    get :preview, on: :member
  end
  resources :collections, only: %i[index create show update destroy] do
    resources :files, only: %i[create destroy], module: :collections
  end
  get "shared", to: "received_sends#index", as: :shared_files
  resources :api_tokens, only: %i[index create destroy], path: "tokens"

  resources :sends, only: %i[index new create show edit update destroy] do
    post :cancel, on: :member
    post :revoke_access, on: :member
    post :rotate_access, on: :member
    resources :revisions, only: :create, module: :sends
    resources :files, only: :show, module: :sends
  end

  get "d/:public_id", to: "deliveries#show", as: :delivery
  post "d/:public_id/access", to: "deliveries/accesses#create", as: :delivery_access
  post "d/:public_id/opened", to: "deliveries/open_events#create", as: :delivery_opened
  get "d/:public_id/files/:id", to: "deliveries/files#show", as: :delivery_file
  post "d/:public_id/files/:id/download", to: "deliveries/files#download", as: :download_delivery_file

  post "mcp", to: "mcp/server#create", as: :mcp_server

  post "api/v1/direct_uploads", to: "api/v1/direct_uploads#create", as: :rails_direct_uploads
  namespace :api do
    namespace :v1 do
      resources :google_drive_imports, only: :create
    end
  end

  get "rails/active_storage/disk/:encoded_key/*filename", to: "active_storage/disk#show", as: :rails_disk_service
  put "rails/active_storage/disk/:encoded_token", to: "active_storage/disk#update", as: :update_rails_disk_service

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
