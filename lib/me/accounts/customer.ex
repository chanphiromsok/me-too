defmodule Me.Accounts.Customer do
  use Ash.Resource,
    otp_app: :me,
    domain: Me.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication, AshJsonApi.Resource]

  json_api do
    type "customer"
  end

  postgres do
    table "customers"
    repo Me.Repo
  end

  actions do
    defaults [:read, :update]

    read :api_index do
      pagination offset?: true, keyset?: true, default_limit: 25, max_page_size: 100
      prepare build(sort: :name)
    end

    create :create_by_staff do
      accept [:name, :email, :phone, :customer_type, :business_name]
      change relate_actor(:created_by)
    end

    read :get_by_subject do
      description "Get a customer by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      filter expr(not is_nil(confirmed_at))
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    update :change_password do
      # Use this action to allow users to change their password by providing
      # their current password and a new password.

      require_atomic? false
      accept []
      argument :current_password, :string, sensitive?: true, allow_nil?: false

      argument :password, :string,
        sensitive?: true,
        allow_nil?: false,
        constraints: [min_length: 8]

      argument :password_confirmation, :string, sensitive?: true, allow_nil?: false

      validate confirm(:password, :password_confirmation)

      validate {AshAuthentication.Strategy.Password.PasswordValidation,
                strategy_name: :password, password_argument: :current_password}

      change {AshAuthentication.Strategy.Password.HashPasswordChange, strategy_name: :password}
    end

    read :sign_in_with_password do
      description "Attempt to sign in using a email and password."
      get? true

      argument :email, :ci_string do
        description "The email to use for retrieving the user."
        allow_nil? false
      end

      argument :password, :string do
        description "The password to check for the matching user."
        allow_nil? false
        sensitive? true
      end

      # Only administrator-approved customers may sign in.
      filter expr(not is_nil(confirmed_at))
      prepare AshAuthentication.Strategy.Password.SignInPreparation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    read :sign_in_with_token do
      # In the generated sign in components, we validate the
      # email and password directly in the LiveView
      # and generate a short-lived token that can be used to sign in over
      # a standard controller action, exchanging it for a standard token.
      # This action performs that exchange. If you do not use the generated
      # liveviews, you may remove this action, and set
      # `sign_in_tokens_enabled? false` in the password strategy.

      description "Attempt to sign in using a short-lived sign in token."
      get? true

      argument :token, :string do
        description "The short-lived sign in token."
        allow_nil? false
        sensitive? true
      end

      # validates the provided sign in token and generates a token
      prepare AshAuthentication.Strategy.Password.SignInWithTokenPreparation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    create :register do
      description "Register a new customer with an email and password."

      accept [:name, :phone, :customer_type]

      argument :email, :ci_string do
        allow_nil? false
      end

      argument :password, :string do
        description "The proposed password for the user, in plain text."
        allow_nil? false
        constraints min_length: 8
        sensitive? true
      end

      argument :password_confirmation, :string do
        description "The proposed password for the user (again), in plain text."
        allow_nil? false
        sensitive? true
      end

      # Sets the email from the argument
      change set_attribute(:email, arg(:email))

      # Hashes the provided password
      change AshAuthentication.Strategy.Password.HashPasswordChange

      # AshAuthentication requires registration to generate a token. It is not
      # exposed by the API and cannot authenticate until an admin confirms the customer.
      change AshAuthentication.GenerateTokenChange

      # validates that the password matches the confirmation
      validate AshAuthentication.Strategy.Password.PasswordConfirmationValidation

      metadata :token, :string do
        description "An internal registration token that remains unusable until confirmation."
        allow_nil? false
      end
    end

    read :get_by_email do
      description "Looks up a user by their email"
      get_by :email
    end

    update :confirm do
      description "Approve a customer account for password sign-in."
      accept []
      change set_attribute(:confirmed_at, &DateTime.utc_now/0)
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action(:create_by_staff) do
      forbid_unless actor_attribute_equals(:active, true)
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :staff)
    end

    policy action([:read, :api_index]) do
      forbid_unless actor_attribute_equals(:active, true)
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :staff)
    end

    policy action(:confirm) do
      forbid_unless actor_attribute_equals(:active, true)
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action([:register, :sign_in_with_password]) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      public? true
    end

    attribute :hashed_password, :string do
      sensitive? true
    end

    attribute :confirmed_at, :utc_datetime_usec do
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :phone, :string do
      public? true
    end

    attribute :customer_type, :atom do
      allow_nil? false
      constraints one_of: [:retail, :wholesale]
      default :retail
      public? true
    end

    attribute :business_name, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :created_by, Me.Accounts.User do
      source_attribute :created_by_user_id
      public? true
    end
  end

  identities do
    identity :unique_email, [:email], nils_distinct?: true
  end

  authentication do
    tokens do
      enabled? true
      token_resource Me.Accounts.Token
      signing_secret Me.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      password :password do
        identity_field :email
        hash_provider AshAuthentication.BcryptProvider
        register_action_name :register
        require_confirmed_with :confirmed_at
      end

      remember_me :remember_me
    end
  end
end
