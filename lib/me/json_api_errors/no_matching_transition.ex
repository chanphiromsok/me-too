defimpl AshJsonApi.ToJsonApiError, for: AshStateMachine.Errors.NoMatchingTransition do
  def to_json_api_error(error) do
    %AshJsonApi.Error{
      id: Ash.UUID.generate(),
      status_code: 409,
      code: "invalid_transition",
      title: "InvalidTransition",
      detail: Exception.message(error),
      meta: %{}
    }
  end
end
