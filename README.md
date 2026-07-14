# Me

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

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
