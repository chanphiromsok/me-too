# Me

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Run the production release locally with Docker

The Compose stack builds an Elixir release, starts PostgreSQL, runs migrations,
loads the idempotent demo seed data, and starts the API on port `4000`.

```sh
docker compose up --build
```

Verify the release and open the API documentation:

```sh
curl http://localhost:4000/health
open http://localhost:4000/api/swaggerui
```

The seeded staff login is `staff@example.com` / `password123`. PostgreSQL is
available to the host on port `5433` to avoid conflicting with a development
database. Override ports when needed:

```sh
API_PORT=4100 POSTGRES_PORT=5434 docker compose up --build
```

Useful lifecycle commands:

```sh
docker compose logs -f api
docker compose down
docker compose down -v # also deletes the local Docker database
```

The checked-in secrets are development-only defaults. Set `SECRET_KEY_BASE`,
`TOKEN_SIGNING_SECRET`, and `POSTGRES_PASSWORD` in the environment before using
this image outside local development. Production builds keep HTTPS redirects
enabled unless the Docker build argument `FORCE_SSL=false` is explicitly used.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Deploy a free testing environment on Render

The repository includes a [`render.yaml`](render.yaml) Blueprint that creates:

- a free Docker web service in Render's Singapore region;
- a free PostgreSQL 17 database in the same region;
- generated signing secrets and a private database connection;
- automatic migrations and idempotent demo data seeding on startup.

Push the repository to GitHub, then in the Render Dashboard choose
**New → Blueprint**, connect the repository, and apply the Blueprint. After the
first deployment finishes, verify these endpoints using the URL Render assigns:

```sh
curl https://YOUR-SERVICE.onrender.com/health
open https://YOUR-SERVICE.onrender.com/api/swaggerui
```

The testing environment uses the same demo login:
`staff@example.com` / `password123`.

The free web service sleeps after 15 minutes without traffic. The free database
is limited to 1 GB, has no backups, and expires after 30 days. Do not enter real
business or payment data. Before production, upgrade both services, remove demo
seeding from `dockerCommand`, and move migrations to Render's pre-deploy command.

## Credit sales and manual payments

Orders use one of two payment terms:

- `immediate` (default): the order must be paid in full before staff can fulfill it.
- `credit`: active staff or admins may approve the customer to receive the order with an unpaid balance.

Customers cannot grant credit to themselves. Staff creates a credit order with
`payment_terms: "credit"`, the customer's `customer_id`, and optionally a
`payment_due_at` timestamp. Order responses expose `total_cents`, `paid_cents`,
`balance_cents`, and `payment_state`.

Payments are recorded manually with
`POST /api/orders/:order_id/payments`. `cash`, `bank_transfer`, `card_manual`,
and `other` describe how staff verified the payment; the backend does not contact
a bank or payment processor. Each payment must be positive and cannot exceed the
remaining order balance. Mistakes are corrected with
`PATCH /api/payments/:id/void`, preserving the audit trail rather than deleting
or editing the original payment.

Active staff and admins can retrieve outstanding customer credit from
`GET /api/receivables`. Each row includes the order balance, due/overdue state,
the customer's total outstanding balance and unpaid-order count, and the total
receivables portfolio balance. Fully paid, cancelled, and returned orders are
excluded.

All money values use integer cents. For example, `$12.50` is sent as `1250`.
The JSON API requires `Content-Type: application/vnd.api+json` for request bodies.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
