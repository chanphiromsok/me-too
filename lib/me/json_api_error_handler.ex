defmodule Me.JsonApiErrorHandler do
  @moduledoc false

  def handle_error(
        %{code: "invalid_attribute", detail: "has already been taken"} = error,
        %{resource: Me.Catalog.ProductVariant}
      ) do
    %{error | status_code: 409, code: "conflict", title: "Conflict"}
  end

  def handle_error(
        %{detail: "would oversell this variant"} = error,
        %{domain: Me.Sales}
      ) do
    %{error | status_code: 422, code: "insufficient_stock", title: "InsufficientStock"}
  end

  def handle_error(error, _context), do: error
end
