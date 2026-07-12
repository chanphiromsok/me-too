# Building the POS API by Hand — Ash + PostgreSQL Tutorial

This is a hands-on walkthrough for building the kids'-clothes POS API on top of
this Phoenix app, using **Ash** and **AshPostgres**. It's written so you type
the code yourself and understand each piece, rather than having it generated
for you. Every section gives you the CLI command to run and the file to
create/edit by hand, in the order things actually need to exist (Ash checks
relationship targets at compile time, so order matters).

Business shape we're building for (recap): a family business selling kids'
clothes. Customers can self-serve order on a web platform, or staff can place
an order on a customer's behalf (phone/in-person). Products are tracked by
size/color variant. Staff have roles. Payments are recorded manually (cash,
bank transfer, etc.) — no payment gateway yet.

---

## 0. Prerequisites

- Postgres running locally and reachable with the credentials in
  `config/dev.exs` (defaults to `postgres`/`postgres` on localhost).
- `mix deps.get` already run at least once (this app already has `igniter`
  installed, which does the heavy lifting for step 1).

---

## 1. Install Ash and friends

Run this once, from the project root:

```sh
mix igniter.install ash ash_postgres ash_json_api ash_authentication ash_state_machine --yes
```

What each one is for:

| Package | Why |
|---|---|
| `ash` | The core resource/domain framework. |
| `ash_postgres` | Postgres data layer + migration generator for Ash resources. |
| `ash_json_api` | Exposes Ash resources as a JSON:API-compliant HTTP API. |
| `ash_authentication` | Password + token (JWT) auth strategies for staff and customers. |
| `ash_state_machine` | Formal state transitions for the `Order` lifecycle (draft → pending → fulfilled/cancelled). |

We're deliberately **not** installing `ash_authentication_phoenix` (it's for
LiveView sign-in forms — this is API-only) or `ash_money` (plain integer
cents is enough for a single-currency shop).

The installer will touch `mix.exs`, `config/config.exs`, and may prompt you
about a few defaults — read each prompt, don't blindly accept.

### 1.1 Teach your AI assistant the Ash rules (`usage_rules`)

Ash's APIs changed a lot between major versions, so LLMs constantly
hallucinate outdated Ash code. The Ash team ships the fix:
[`usage_rules`](https://github.com/ash-project/usage_rules) syncs each
dependency's `usage-rules.md` (their "how an LLM should write code against
this package" guide) into `AGENTS.md`. This repo's `AGENTS.md` already
contains usage-rules blocks for Phoenix — same mechanism, so Ash slots
right in.

```sh
mix igniter.install usage_rules
```

Then configure it in `mix.exs` (inside `project/0`, plus a private
function):

```elixir
def project do
  [
    # ...existing keys...
    usage_rules: usage_rules()
  ]
end

defp usage_rules do
  [
    file: "AGENTS.md",
    usage_rules: [
      "usage_rules:elixir",
      "usage_rules:otp",
      "phoenix:elixir",
      "phoenix:phoenix",
      "phoenix:ecto",
      "phoenix:html",
      "phoenix:liveview",
      :ash,
      ~r/^ash_/
    ]
  ]
end
```

and sync:

```sh
mix usage_rules.sync
```

Two things to know:

- **The config is the source of truth** — any package block in `AGENTS.md`
  that isn't listed in the config gets *removed* on sync. That's why the
  existing `phoenix:*` sub-rules are listed explicitly above; leave them
  out and the sync deletes them.
- `~r/^ash_/` future-proofs the list: `ash_postgres`, `ash_json_api`,
  `ash_authentication`, `ash_state_machine` (and anything you add later,
  like `ash_paper_trail`) are picked up automatically.

Re-run `mix usage_rules.sync` after adding any new dependency. There's
also `mix usage_rules.search_docs "your query" -p ash` for searching
hexdocs from the terminal — handy for the fill-in-yourself TODOs later in
this tutorial.

---

## 2. The domain map

Four Ash **domains**, each a plain Elixir module + a folder of resources:

```
lib/me/
  accounts/        Me.Accounts        — User (staff), Customer, Token
  catalog/          Me.Catalog         — Product, ProductVariant
  inventory/        Me.Inventory       — StockMovement
  sales/            Me.Sales           — Order, OrderLineItem, Payment
```

Build them in this order — `accounts` first (everything references
`User`/`Customer`), then `catalog`, then `inventory` (needs `ProductVariant`),
then `sales` (needs all three).

---

## 3. `Me.Accounts` — staff, customers, auth

### 3.1 Generate the domain

```sh
mkdir -p lib/me/accounts
```

Create `lib/me/accounts.ex` by hand:

```elixir
defmodule Me.Accounts do
  use Ash.Domain

  resources do
    resource Me.Accounts.Token
    resource Me.Accounts.User
    resource Me.Accounts.Customer
  end
end
```

### 3.2 `User` (staff)

Create `lib/me/accounts/user.ex`. Type this out — don't skip reading each
`attribute`/`relationship` line, this is the shape you'll repeat for every
other resource:

```elixir
defmodule Me.Accounts.User do
  use Ash.Resource,
    otp_app: :me,
    domain: Me.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication]

  postgres do
    table "users"
    repo Me.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :email, :ci_string, allow_nil?: false, public?: true
    attribute :hashed_password, :string, allow_nil?: false, sensitive?: true
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :role, :atom, constraints: [one_of: [:admin, :staff]], default: :staff, public?: true
    attribute :active, :boolean, default: true, public?: true
    timestamps()
  end

  identities do
    identity :unique_email, [:email]
  end

  authentication do
    # fill in with the password + token strategy per ash_authentication's
    # own generated getting-started docs (`mix hex.docs open ash_authentication`)
  end

  actions do
    defaults [:read]
    # no destroy — deactivate via `active: false` instead

    update :deactivate do
      accept []
      change set_attribute(:active, false)
    end
  end
end
```

Leave yourself a `# TODO` on the `authentication do` block — `ash_authentication`
ships a generator (`mix ash_authentication.add_strategy password`) that will
fill this in correctly for you; run it against this resource rather than
hand-writing the strategy config, since the token/hashing details are easy to
get subtly wrong by hand.

### 3.3 `Customer`

Create `lib/me/accounts/customer.ex` following the same shape as `User`, but:

- `email` is **nullable** (not every walk-in customer has one)
- add `phone`, `customer_type` (`:retail | :wholesale`), `business_name` (nullable)
- add `created_by_user_id`, a `belongs_to :created_by, Me.Accounts.User` (nullable)
- two create actions instead of relying on the default:

```elixir
actions do
  defaults [:read, :update]

  create :register do
    accept [:name, :email, :phone, :customer_type]
    argument :password, :string, allow_nil?: false, sensitive?: true
    # hash the password into :hashed_password here, per ash_authentication docs
  end

  create :create_by_staff do
    accept [:name, :email, :phone, :customer_type, :business_name]
    change relate_actor(:created_by)
    # no password required — this customer can't sign in yet
  end
end
```

`relate_actor/1` is an Ash built-in change — look it up
(`h Ash.Resource.Change.Builtins.relate_actor`) rather than hand-rolling the
`actor()` lookup yourself.

### 3.4 `Token`

Generate this one from `ash_authentication`'s own generator instead of typing
it by hand — it's boilerplate you don't want to get wrong:

```sh
mix ash_authentication.add_strategy password
```

Follow the prompts, pointing it at `Me.Accounts.User` first, then re-run for
`Me.Accounts.Customer`. It will create/update `lib/me/accounts/token.ex` for
you.

### 3.5 Migrate

```sh
mix ash_postgres.generate_migrations --name create_accounts
mix ash_postgres.migrate
```

Open the generated migration under `priv/repo/migrations/` and read it before
running — confirm it matches what you expect (a `users` table, a `customers`
table, a `tokens` table).

---

## 4. `Me.Catalog` — products

Create `lib/me/catalog.ex`:

```elixir
defmodule Me.Catalog do
  use Ash.Domain

  resources do
    resource Me.Catalog.Product
    resource Me.Catalog.ProductVariant
  end
end
```

`lib/me/catalog/product.ex`:

```elixir
defmodule Me.Catalog.Product do
  use Ash.Resource,
    otp_app: :me,
    domain: Me.Catalog,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "products"
    repo Me.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :description, :string, public?: true
    attribute :category, :string, public?: true
    attribute :status, :atom, constraints: [one_of: [:active, :archived]], default: :active, public?: true
    timestamps()
  end

  relationships do
    has_many :variants, Me.Catalog.ProductVariant
  end

  actions do
    defaults [:read, :create, :update]

    update :archive do
      accept []
      change set_attribute(:status, :archived)
    end
  end
end
```

`lib/me/catalog/product_variant.ex` — this is the one with the size/color
tracking you asked for:

```elixir
defmodule Me.Catalog.ProductVariant do
  use Ash.Resource,
    otp_app: :me,
    domain: Me.Catalog,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "product_variants"
    repo Me.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :sku, :string, allow_nil?: false, public?: true
    attribute :size, :string, allow_nil?: false, public?: true
    attribute :color, :string, allow_nil?: false, public?: true
    attribute :price_cents, :integer, allow_nil?: false, public?: true
    attribute :quantity_on_hand, :integer, default: 0, public?: true
    attribute :barcode, :string, public?: true
    attribute :active, :boolean, default: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :product, Me.Catalog.Product, allow_nil?: false
  end

  identities do
    identity :unique_sku, [:sku]
    identity :unique_product_size_color, [:product_id, :size, :color]
  end

  actions do
    defaults [:read, :create, :update]
  end
end
```

Then generate a raw SQL check constraint by hand in the migration (Ash won't
generate `CHECK (quantity_on_hand >= 0)` for you automatically) — after
running `mix ash_postgres.generate_migrations --name create_catalog`, open the
new migration file and add:

```elixir
create constraint(:product_variants, :quantity_on_hand_non_negative,
  check: "quantity_on_hand >= 0"
)
```

```sh
mix ash_postgres.migrate
```

---

## 5. `Me.Inventory` — stock ledger

Create `lib/me/inventory.ex`:

```elixir
defmodule Me.Inventory do
  use Ash.Domain

  resources do
    resource Me.Inventory.StockMovement
  end
end
```

`lib/me/inventory/stock_movement.ex` — the important part here is that it's
**insert-only** (no update/destroy actions at all):

```elixir
defmodule Me.Inventory.StockMovement do
  use Ash.Resource,
    otp_app: :me,
    domain: Me.Inventory,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "stock_movements"
    repo Me.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :delta, :integer, allow_nil?: false, public?: true
    attribute :reason, :atom,
      constraints: [one_of: [:restock, :sale, :cancellation_restock, :adjustment]],
      allow_nil?: false,
      public?: true
    attribute :reference_type, :string, public?: true
    attribute :reference_id, :uuid, public?: true
    attribute :note, :string, public?: true
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :product_variant, Me.Catalog.ProductVariant, allow_nil?: false
    belongs_to :actor, Me.Accounts.User, allow_nil?: true
  end

  actions do
    defaults [:read]
    # deliberately: no :create in defaults, no :update, no :destroy —
    # write a custom create action below that does the locked counter update
  end
end
```

The custom `create` action is the trickiest part of this whole tutorial —
it needs to, in one transaction: lock the variant row, check the resulting
`quantity_on_hand` won't go negative (unless `reason: :adjustment`), insert
the movement, and update the variant's counter. Type this by hand and read
each line — this is the piece that actually prevents overselling:

```elixir
create :apply do
  accept [:delta, :reason, :reference_type, :reference_id, :note, :product_variant_id]
  change relate_actor(:actor, allow_nil?: true)

  change fn changeset, _context ->
    Ash.Changeset.before_action(changeset, fn changeset ->
      variant_id = Ash.Changeset.get_attribute(changeset, :product_variant_id)
      delta = Ash.Changeset.get_attribute(changeset, :delta)
      reason = Ash.Changeset.get_attribute(changeset, :reason)

      variant =
        Me.Catalog.ProductVariant
        |> Ash.Query.filter(id == ^variant_id)
        |> Ash.Query.lock(:for_update)
        |> Ash.read_one!()

      new_quantity = variant.quantity_on_hand + delta

      if new_quantity < 0 and reason != :adjustment do
        Ash.Changeset.add_error(changeset, field: :delta, message: "would oversell this variant")
      else
        Ash.update!(variant, %{quantity_on_hand: new_quantity})
        changeset
      end
    end)
  end
end
```

```sh
mix ash_postgres.generate_migrations --name create_inventory
mix ash_postgres.migrate
```

---

## 6. `Me.Sales` — orders, line items, payments

Create `lib/me/sales.ex`:

```elixir
defmodule Me.Sales do
  use Ash.Domain

  resources do
    resource Me.Sales.Order
    resource Me.Sales.OrderLineItem
    resource Me.Sales.Payment
  end
end
```

### 6.1 `Order` with a state machine

`lib/me/sales/order.ex`:

```elixir
defmodule Me.Sales.Order do
  use Ash.Resource,
    otp_app: :me,
    domain: Me.Sales,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine]

  postgres do
    table "orders"
    repo Me.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :order_number, :integer, generated?: true, public?: true
    attribute :status, :atom,
      constraints: [one_of: [:draft, :pending, :fulfilled, :cancelled]],
      default: :draft,
      public?: true
    attribute :subtotal_cents, :integer, default: 0, public?: true
    attribute :discount_cents, :integer, default: 0, public?: true
    attribute :placed_at, :utc_datetime, public?: true
    attribute :fulfilled_at, :utc_datetime, public?: true
    attribute :cancelled_at, :utc_datetime, public?: true
    attribute :cancel_reason, :string, public?: true
    timestamps()
  end

  relationships do
    belongs_to :customer, Me.Accounts.Customer, allow_nil?: false
    belongs_to :placed_by, Me.Accounts.User, allow_nil?: true
    has_many :line_items, Me.Sales.OrderLineItem
    has_many :payments, Me.Sales.Payment
  end

  calculations do
    calculate :total_cents, :integer, expr(subtotal_cents - discount_cents)
    # payment_state: sum non-voided payments, compare to total_cents —
    # write this as an Ash calculation once you've read the AshStateMachine
    # and Ash calculations docs; it's the same "derive, never store" idea
    # as total_cents above.
  end

  state_machine do
    initial_states [:draft]
    default_initial_state :draft

    transitions do
      transition :submit, from: :draft, to: :pending
      transition :fulfill, from: :pending, to: :fulfilled
      transition :cancel, from: [:draft, :pending], to: :cancelled
    end
  end

  actions do
    defaults [:read, :create, :update]

    update :submit do
      change transition_state(:pending)
      change set_attribute(:placed_at, &DateTime.utc_now/0)
      # then, for each line item, call Me.Inventory.StockMovement's :apply
      # action with reason: :sale and a negative delta — this is the
      # "decrement stock at submission" rule from the design.
    end

    update :fulfill do
      change transition_state(:fulfilled)
      change set_attribute(:fulfilled_at, &DateTime.utc_now/0)
    end

    update :cancel do
      accept [:cancel_reason]
      change transition_state(:cancelled)
      change set_attribute(:cancelled_at, &DateTime.utc_now/0)
      # if status was :pending, emit compensating :cancellation_restock
      # StockMovements here, mirroring :submit above.
    end
  end
end
```

Two spots above are intentionally left as comments for you to fill in
(the stock-movement calls inside `:submit`/`:cancel`, and the `payment_state`
calculation) — work through the `Ash.Changeset.after_action/2` and
`Ash.calculate/2` docs to write them yourself; they follow the same pattern
as the locked update you already wrote in `StockMovement.apply`.

### 6.2 `OrderLineItem`

`lib/me/sales/order_line_item.ex` — same shape as before: `belongs_to :order`,
`belongs_to :product_variant`, `quantity`, `unit_price_cents` (snapshot this
from the variant's current price when the line is added, don't read it live
later), and a `line_total_cents` calculation (`quantity * unit_price_cents`).

### 6.3 `Payment`

`lib/me/sales/payment.ex` — insert-only like `StockMovement`: `belongs_to
:order`, `amount_cents`, `method` (atom: `:cash | :bank_transfer |
:card_manual | :other`), `belongs_to :recorded_by, Me.Accounts.User,
allow_nil?: false`, `recorded_at`, `note`, `voided_at` (nullable). Give it a
`:void` update action (`change set_attribute(:voided_at, &DateTime.utc_now/0)`)
instead of a destroy action.

### 6.4 Where customers see their orders (the "invoice")

No separate invoice resource, no PDF. The order **is** the receipt, and
the read endpoints you already built serve it:

- `GET /api/orders?sort=-placed_at` — a customer's order history (policy
  scopes the list to their own orders automatically)
- `GET /api/orders/:id?include=line_items.product_variant,payments` —
  the full receipt: `order_number`, each line at the price actually
  charged, totals, `payment_state`, payment trail

This is trustworthy as an invoice because of two decisions already in
your model: `unit_price_cents` was snapshotted onto each line item when
it was added, and line items are frozen once the order leaves `draft`.
An order from last year always shows what was actually charged, no
matter how prices moved since. The frontend renders the JSON however it
wants — screen, print stylesheet, shared image.

If the business ever needs formal numbered invoices for bookkeeping
(unbroken invoice-number series, frozen bill-to details, PDF export),
that becomes a snapshot `Invoice` resource issued in `Order.submit`'s
transaction — nothing in the current model blocks adding it later.

### 6.5 Migrate

```sh
mix ash_postgres.generate_migrations --name create_sales
mix ash_postgres.migrate
```

---

## 7. Wire up the router

Edit `lib/me_web/router.ex`. Replace the commented-out placeholder:

```elixir
# scope "/api", MeWeb do
#   pipe_through :api
# end
```

with an `AshJsonApi.Router` forward, and add the bearer-token plug to the
`:api` pipeline first:

```elixir
pipeline :api do
  plug :accepts, ["json"]
  plug AshAuthentication.Plug.Helpers
  # resolve the bearer token into conn.assigns / the Ash actor here —
  # follow ash_authentication's own docs for the exact plug wiring, since
  # it changed a couple of times across versions.
end

scope "/api" do
  pipe_through :api
  forward "/", MeWeb.AshJsonApiRouter
end
```

Create `lib/me_web/ash_json_api_router.ex`:

```elixir
defmodule MeWeb.AshJsonApiRouter do
  use AshJsonApi.Router,
    domains: [Me.Accounts, Me.Catalog, Me.Inventory, Me.Sales]
end
```

Then, per-resource, add a `json_api do ... end` block (routes, exposed
actions) to each resource you want reachable over HTTP — see the design
notes in this repo's plan for exactly which actions get exposed per
resource (`Product`/`ProductVariant` public read, `Order`/`Payment`
staff-and-owner-gated writes, `StockMovement` **not** exposed generically).

---

## 8. Try it by hand

```sh
mix phx.server
```

In another terminal:

```sh
# register a customer
curl -X POST localhost:4000/api/customers \
  -H "Content-Type: application/vnd.api+json" \
  -d '{"data":{"type":"customer","attributes":{"name":"Test Parent","email":"test@example.com","password":"..."}}}'

# browse products anonymously
curl localhost:4000/api/products
```

Work through the full flow yourself: sign in, create a draft order, add a
line item, submit it, confirm `quantity_on_hand` dropped, record a payment,
confirm the order's payment state moves toward `:paid`.

---

## 9. What's deliberately left out of this tutorial

Returns/refunds, discount codes, tax handling, wholesale credit terms,
low-stock alerts, and reporting endpoints are all out of scope for this first
pass — see the plan discussion for why each one is deferred rather than
forgotten. Come back to them once the core flow above works end-to-end.
