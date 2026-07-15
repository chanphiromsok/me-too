defmodule Me.Accounts.User do
  use Ash.Resource,
    otp_app: :me,
    domain: Me.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication, AshJsonApi.Resource]

  json_api do
    type "user"
  end

  postgres do
    table "users"
    repo Me.Repo
  end

  actions do
    defaults [:read]

    read :get_by_subject do
      description "Get a user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      filter expr(active == true)
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

      # validates the provided email and password and generates a token
      filter expr(active == true)
      prepare AshAuthentication.Strategy.Password.SignInPreparation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    create :register_with_password do
      description "Register a new user with a email and password."

      accept [:role]

      argument :email, :ci_string do
        allow_nil? false
      end

      argument :name, :string do
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
      change set_attribute(:name, arg(:name))

      # Hashes the provided password
      change AshAuthentication.Strategy.Password.HashPasswordChange

      # Generates an authentication token for the user
      change AshAuthentication.GenerateTokenChange

      # validates that the password matches the confirmation
      validate AshAuthentication.Strategy.Password.PasswordConfirmationValidation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    read :get_by_email do
      description "Looks up a user by their email"
      get_by :email
    end

    update :deactivate do
      accept []
      change set_attribute(:active, false)
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action(:sign_in_with_password) do
      authorize_if always()
    end

    policy action(:register_with_password) do
      forbid_unless actor_attribute_equals(:active, true)
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action(:deactivate) do
      forbid_unless actor_attribute_equals(:active, true)
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action(:read) do
      authorize_if actor_present()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :hashed_password, :string do
      allow_nil? false
      sensitive? true
    end

    attribute :confirmed_at, :utc_datetime_usec

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :role, :atom do
      allow_nil? false
      constraints one_of: [:admin, :staff]
      default :staff
      public? true
    end

    attribute :active, :boolean do
      allow_nil? false
      default true
      public? true
    end

    timestamps()
  end

  identities do
    identity :unique_email, [:email]
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
        sign_in_tokens_enabled? false
      end

      remember_me :remember_me
    end

    add_ons do
      log_out_everywhere do
        apply_on_password_change? true
      end
    end
  end
end
