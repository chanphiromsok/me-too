defmodule Me.Repo.Migrations.AddCreditSalesAndReceivables do
  use Ecto.Migration

  def up do
    alter table(:orders) do
      add :payment_terms, :text, null: false, default: "immediate"
      add :payment_due_at, :utc_datetime_usec
    end

    create constraint(:orders, :orders_payment_terms_valid,
             check: "payment_terms IN ('immediate', 'credit')"
           )

    create index(:orders, [:customer_id, :payment_due_at],
             name: :orders_credit_receivables_index,
             where: "payment_terms = 'credit' AND status IN ('pending', 'fulfilled')"
           )

    execute("""
    CREATE VIEW receivables AS
    WITH payment_totals AS (
      SELECT
        order_id,
        COALESCE(SUM(amount_cents) FILTER (WHERE voided_at IS NULL), 0)::bigint AS paid_cents
      FROM payments
      GROUP BY order_id
    ),
    outstanding AS (
      SELECT
        orders.id,
        orders.order_number,
        orders.order_kind,
        orders.status,
        orders.customer_id,
        customers.name AS customer_name,
        customers.phone AS customer_phone,
        (orders.subtotal_cents - orders.discount_cents)::bigint AS total_cents,
        COALESCE(payment_totals.paid_cents, 0)::bigint AS paid_cents,
        GREATEST(
          (orders.subtotal_cents - orders.discount_cents) -
            COALESCE(payment_totals.paid_cents, 0),
          0
        )::bigint AS balance_cents,
        orders.payment_due_at,
        (
          orders.payment_due_at IS NOT NULL AND
          orders.payment_due_at < (now() AT TIME ZONE 'utc')
        ) AS overdue,
        orders.placed_at
      FROM orders
      INNER JOIN customers ON customers.id = orders.customer_id
      LEFT JOIN payment_totals ON payment_totals.order_id = orders.id
      WHERE orders.payment_terms = 'credit'
        AND orders.status IN ('pending', 'fulfilled')
    )
    SELECT
      outstanding.*,
      SUM(balance_cents) OVER (PARTITION BY customer_id)::bigint AS customer_balance_cents,
      COUNT(*) OVER (PARTITION BY customer_id)::bigint AS customer_unpaid_order_count,
      SUM(balance_cents) OVER ()::bigint AS portfolio_balance_cents
    FROM outstanding
    WHERE balance_cents > 0
    """)
  end

  def down do
    execute("DROP VIEW receivables")

    drop_if_exists index(:orders, [:customer_id, :payment_due_at],
                     name: :orders_credit_receivables_index
                   )

    drop constraint(:orders, :orders_payment_terms_valid)

    alter table(:orders) do
      remove :payment_due_at
      remove :payment_terms
    end
  end
end
