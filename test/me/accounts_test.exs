defmodule Me.AccountsTest do
  use Me.DataCase, async: true

  alias AshAuthentication.Jwt
  alias Me.Accounts.{Customer, User}
  alias Me.Sales.Order

  @password "password123"

  test "staff can sign in with a valid JWT, but deactivated staff cannot" do
    staff = create_staff!()

    assert {:ok, signed_in_staff} = sign_in(User, staff.email)
    assert is_binary(signed_in_staff.__metadata__.token)
    assert {:ok, _claims, User} = Jwt.verify(signed_in_staff.__metadata__.token, User)

    assert {:ok, deactivated_staff} =
             Ash.update(staff, %{}, action: :deactivate, authorize?: false)

    refute deactivated_staff.active
    refute match?({:ok, %User{}}, sign_in(User, staff.email))
  end

  test "staff can approve, suspend, and return a customer to review" do
    staff = create_staff!()
    email = unique_email("customer")

    assert {:ok, customer} =
             Ash.create(
               Customer,
               %{
                 name: "Retail Customer",
                 email: email,
                 phone: "012345678",
                 customer_type: :retail,
                 password: @password,
                 password_confirmation: @password
               },
               action: :register
             )

    assert customer.hashed_password
    refute customer.hashed_password == @password
    assert is_nil(customer.confirmed_at)
    assert customer.status == :needs_approval
    refute match?({:ok, %Customer{}}, sign_in(Customer, email))

    assert {:ok, confirmed_customer} =
             Ash.update(customer, %{}, action: :confirm, actor: staff)

    assert %DateTime{} = confirmed_customer.confirmed_at
    assert confirmed_customer.status == :approved

    assert {:ok, signed_in_customer} = sign_in(Customer, email)
    assert is_binary(signed_in_customer.__metadata__.token)

    assert {:ok, _claims, Customer} =
             Jwt.verify(signed_in_customer.__metadata__.token, Customer)

    assert {:ok, suspended_customer} =
             Ash.update(confirmed_customer, %{}, action: :suspend, actor: staff)

    assert suspended_customer.status == :suspended
    refute match?({:ok, %Customer{}}, sign_in(Customer, email))

    assert {:ok, pending_customer} =
             Ash.update(suspended_customer, %{}, action: :require_approval, actor: staff)

    assert pending_customer.status == :needs_approval
    assert is_nil(pending_customer.confirmed_at)
  end

  test "suspended customers cannot receive new orders" do
    staff = create_staff!()

    customer =
      Customer
      |> Ash.create!(
        %{name: "Suspended Customer", customer_type: :retail},
        action: :create_by_staff,
        actor: staff
      )
      |> Ash.update!(%{}, action: :suspend, actor: staff)

    assert {:error, error} =
             Ash.create(Order, %{customer_id: customer.id}, actor: staff)

    assert Exception.message(error) =~ "suspended customers cannot create new orders"
  end

  test "active staff can create password-less walk-in customers" do
    staff = create_staff!()

    assert {:ok, first_walk_in} =
             Ash.create(
               Customer,
               %{name: "Walk-in Customer", phone: "099999999", customer_type: :retail},
               action: :create_by_staff,
               actor: staff
             )

    assert first_walk_in.created_by_user_id == staff.id
    assert is_nil(first_walk_in.email)
    assert is_nil(first_walk_in.hashed_password)

    assert {:ok, second_walk_in} =
             Ash.create(
               Customer,
               %{name: "Another Walk-in", customer_type: :wholesale},
               action: :create_by_staff,
               actor: staff
             )

    assert is_nil(second_walk_in.email)

    assert {:error, _error} =
             Ash.create(
               Customer,
               %{name: "Unauthorized Walk-in", customer_type: :retail},
               action: :create_by_staff
             )
  end

  test "staff and customer emails are unique case-insensitively" do
    staff_email = unique_email("unique-staff")
    customer_email = unique_email("unique-customer")

    _staff = create_staff!(email: staff_email)

    assert {:error, %Ash.Error.Invalid{}} =
             create_staff(String.upcase(staff_email))

    assert {:ok, _customer} = register_customer(customer_email)

    assert {:error, %Ash.Error.Invalid{}} =
             register_customer(String.upcase(customer_email))
  end

  defp create_staff!(opts \\ []) do
    email = Keyword.get(opts, :email, unique_email("staff"))
    role = Keyword.get(opts, :role, :staff)
    {:ok, staff} = create_staff(email, role)
    staff
  end

  defp create_staff(email, role \\ :staff) do
    Ash.create(
      User,
      %{
        name: "Test Staff",
        email: email,
        role: role,
        password: @password,
        password_confirmation: @password
      },
      action: :register_with_password,
      authorize?: false
    )
  end

  defp register_customer(email) do
    Ash.create(
      Customer,
      %{
        name: "Test Customer",
        email: email,
        customer_type: :retail,
        password: @password,
        password_confirmation: @password
      },
      action: :register
    )
  end

  defp sign_in(resource, email) do
    resource
    |> Ash.Query.for_read(:sign_in_with_password, %{email: email, password: @password})
    |> Ash.read_one()
  end

  defp unique_email(prefix) do
    "#{prefix}-#{System.unique_integer([:positive])}@example.com"
  end
end
