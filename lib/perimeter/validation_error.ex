defmodule Perimeter.ValidationError do
  @moduledoc """
  Exception raised when validation fails at a guarded perimeter.

  Contains detailed information about all validation violations.
  """

  defexception [:message, :violations]

  @type t :: %__MODULE__{
          message: String.t(),
          violations: [violation()]
        }

  @type violation :: %{
          field: atom(),
          error: String.t(),
          path: [atom()]
        }

  @doc """
  Creates a new ValidationError from a list of violations.
  """
  def new(violations) when is_list(violations) do
    message = format_message(violations)
    %__MODULE__{message: message, violations: violations}
  end

  @impl true
  def exception(violations) when is_list(violations) do
    new(violations)
  end

  defp format_message(violations) do
    violation_details = Enum.map_join(violations, "\n  - ", &format_violation/1)

    """
    Validation failed at perimeter with #{length(violations)} violation(s):
      - #{violation_details}
    """
  end

  defp format_violation(%{field: field, error: error, path: []}) do
    "#{field}: #{error}"
  end

  defp format_violation(%{field: field, error: error, path: path}) do
    path_str = Enum.join(path, ".")
    "#{path_str}.#{field}: #{error}"
  end
end
