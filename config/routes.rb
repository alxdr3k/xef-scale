Rails.application.routes.draw do
  devise_for :users, controllers: {
    omniauth_callbacks: "users/omniauth_callbacks"
  }

  # Test login (development/test only)
  if Rails.env.development? || Rails.env.test?
    get "test_login", to: "test_sessions#create"
  end

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Landing page (unauthenticated root)
  unauthenticated do
    root "pages#landing", as: :unauthenticated_root
  end

  # Authenticated routes
  authenticated :user do
    root "dashboards#monthly", as: :authenticated_root
  end

  # Default root
  root "pages#landing"

  # Workspaces
  resources :workspaces do
    member do
      get :settings
    end

    # Workspace memberships
    resources :memberships, controller: "workspace_memberships", only: [ :index, :update, :destroy ]

    # Workspace invitations
    resources :invitations, controller: "workspace_invitations", only: [ :index, :create, :destroy ]

    # Transactions within workspace
    resources :transactions do
      member do
        post :toggle_allowance
        patch :quick_update_category
        patch :inline_update
      end
      collection do
        get :export
        get :suggest_category
      end
    end

    # Categories within workspace
    resources :categories, except: [ :show ]

    # File uploads and parsing
    resources :parsing_sessions, only: [ :index, :show, :create ] do
      collection do
        post :create_from_text
      end
      resources :duplicate_confirmations, only: [ :update ]
      member do
        get :review, to: "reviews#show"
        post :commit, to: "reviews#commit"
        post :rollback, to: "reviews#rollback"
        post :discard, to: "reviews#discard"
        post :bulk_update, to: "reviews#bulk_update"
        post :bulk_resolve_duplicates, to: "reviews#bulk_resolve_duplicates"
        patch "transactions/:transaction_id", to: "reviews#update_transaction", as: :update_transaction
      end
    end
  end

  # Join workspace via invitation link
  get "join/:token", to: "workspace_invitations#join", as: :join_workspace

  # Allowance tracking
  resources :allowances, only: [ :index ]

  # Dashboard
  resource :dashboard, only: [] do
    get :monthly, action: :monthly
    get :yearly, action: :yearly
    get "category_transactions/:category_id", action: :category_transactions, as: :category_transactions
  end
  get "dashboard", to: "dashboards#monthly", as: :dashboard

  # User Settings
  resource :user_settings, only: [ :show, :update ], path: "settings"

  # Notifications
  resources :notifications, only: [ :index ] do
    member do
      post :mark_read
    end
    collection do
      post :mark_all_read
      get :unread_count
    end
  end
end
