Rails.application.routes.draw do
  devise_for :users, controllers: {
    omniauth_callbacks: 'users/omniauth_callbacks'
  }

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Landing page (unauthenticated root)
  unauthenticated do
    root 'pages#landing', as: :unauthenticated_root
  end

  # Authenticated routes
  authenticated :user do
    root 'dashboards#show', as: :authenticated_root
  end

  # Default root
  root 'pages#landing'

  # Workspaces
  resources :workspaces do
    member do
      get :settings
    end

    # Workspace memberships
    resources :memberships, controller: 'workspace_memberships', only: [:index, :update, :destroy]

    # Workspace invitations
    resources :invitations, controller: 'workspace_invitations', only: [:index, :create, :destroy]

    # Transactions within workspace
    resources :transactions do
      member do
        post :toggle_allowance
      end
      collection do
        get :export
      end
    end

    # Categories within workspace
    resources :categories, except: [:show]

    # File uploads and parsing
    resources :parsing_sessions, only: [:index, :show, :create] do
      resources :duplicate_confirmations, only: [:update]
    end
  end

  # Join workspace via invitation link
  get 'join/:token', to: 'workspace_invitations#join', as: :join_workspace

  # Allowance tracking
  resources :allowances, only: [:index]

  # Dashboard
  resource :dashboard, only: [:show]
end
