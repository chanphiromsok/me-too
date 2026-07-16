defmodule Me.Inventory.StockMovement do
  use Ash.Resource,
    otp_app: :me,
    domain: Me.Inventory,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  json_api do
    type "stock_movement"
  end

  postgres do
    table "stock_movements"
    repo Me.Repo
  end

  actions do
    defaults [:read]

    read :for_variant do
      argument :product_variant_id, :uuid, allow_nil?: false
      filter expr(product_variant_id == ^arg(:product_variant_id))
    end

    read :api_for_variant do
      argument :product_variant_id, :uuid, allow_nil?: false
      filter expr(product_variant_id == ^arg(:product_variant_id))
      pagination offset?: true, keyset?: true, default_limit: 25, max_page_size: 100
    end

    create :apply do
      public? false

      accept [
        :delta,
        :reason,
        :reference_type,
        :reference_id,
        :note
      ]

      argument :product_variant_id, :uuid, allow_nil?: false

      change set_attribute(:product_variant_id, arg(:product_variant_id))
      change relate_actor(:actor, allow_nil?: true)
      change Me.Inventory.Changes.ApplyStockMovement
    end

    create :restock do
      accept [:reference_type, :reference_id, :note]
      argument :product_variant_id, :uuid, allow_nil?: false
      argument :quantity, :integer, allow_nil?: false, constraints: [min: 1]

      change set_attribute(:product_variant_id, arg(:product_variant_id))
      change set_attribute(:reason, :restock)
      change {Me.Inventory.Changes.SetSignedDelta, sign: :positive}
      change relate_actor(:actor, allow_nil?: true)
      change Me.Inventory.Changes.ApplyStockMovement
    end

    create :sale do
      accept [:reference_type, :reference_id, :note]
      argument :product_variant_id, :uuid, allow_nil?: false
      argument :quantity, :integer, allow_nil?: false, constraints: [min: 1]

      change set_attribute(:product_variant_id, arg(:product_variant_id))
      change set_attribute(:reason, :sale)
      change {Me.Inventory.Changes.SetSignedDelta, sign: :negative}
      change relate_actor(:actor, allow_nil?: true)
      change Me.Inventory.Changes.ApplyStockMovement
    end

    create :cancellation_restock do
      accept [:reference_type, :reference_id, :note]
      argument :product_variant_id, :uuid, allow_nil?: false
      argument :quantity, :integer, allow_nil?: false, constraints: [min: 1]

      change set_attribute(:product_variant_id, arg(:product_variant_id))
      change set_attribute(:reason, :cancellation_restock)
      change {Me.Inventory.Changes.SetSignedDelta, sign: :positive}
      change relate_actor(:actor, allow_nil?: true)
      change Me.Inventory.Changes.ApplyStockMovement
    end

    create :return_restock do
      accept [:reference_type, :reference_id, :note]
      argument :product_variant_id, :uuid, allow_nil?: false
      argument :quantity, :integer, allow_nil?: false, constraints: [min: 1]

      change set_attribute(:product_variant_id, arg(:product_variant_id))
      change set_attribute(:reason, :return_restock)
      change {Me.Inventory.Changes.SetSignedDelta, sign: :positive}
      change relate_actor(:actor, allow_nil?: true)
      change Me.Inventory.Changes.ApplyStockMovement
    end

    create :adjust do
      accept [:reference_type, :reference_id, :note]
      argument :product_variant_id, :uuid, allow_nil?: false
      argument :quantity, :integer, allow_nil?: false, constraints: [min: 1]

      argument :direction, :atom,
        allow_nil?: false,
        constraints: [one_of: [:increase, :decrease]]

      change set_attribute(:product_variant_id, arg(:product_variant_id))
      change set_attribute(:reason, :adjustment)
      change {Me.Inventory.Changes.SetSignedDelta, sign: :from_direction}
      change relate_actor(:actor, allow_nil?: true)
      change Me.Inventory.Changes.ApplyStockMovement
    end
  end

  policies do
    policy action_type([:read, :create]) do
      access_type :strict

      forbid_unless actor_attribute_equals(:active, true)
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :staff)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :delta, :integer do
      allow_nil? false
      public? true
    end

    attribute :reason, :atom do
      allow_nil? false

      constraints one_of: [
                    :restock,
                    :sale,
                    :cancellation_restock,
                    :return_restock,
                    :adjustment
                  ]

      public? true
    end

    attribute :reference_type, :string do
      allow_nil? false
      default "manual_inventory_operation"
      public? true
    end

    attribute :reference_id, :uuid do
      allow_nil? false
      default &Ash.UUID.generate/0
      public? true
    end

    attribute :note, :string do
      public? true
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :product_variant, Me.Catalog.ProductVariant do
      allow_nil? false
      public? true
    end

    belongs_to :actor, Me.Accounts.User do
      public? true
    end
  end

  identities do
    identity :unique_reference,
             [:product_variant_id, :reason, :reference_type, :reference_id]
  end
end
