defmodule Perimeter.Validator do
  @moduledoc """
  Runtime validation engine for Perimeter contracts.

  Validates data against defined contracts and returns detailed error information
  when validation fails.

  ## Example

      defmodule MyContract do
        use Perimeter.Contract

        defcontract :user do
          required :email, :string, format: ~r/@/
          required :age, :integer, min: 0
        end
      end

      # Valid data
      Validator.validate(MyContract, :user, %{email: "a@b.com", age: 25})
      # => {:ok, %{email: "a@b.com", age: 25}}

      # Invalid data
      Validator.validate(MyContract, :user, %{email: "invalid", age: -1})
      # => {:error, [
      #      %{field: :email, error: "does not match format", path: []},
      #      %{field: :age, error: "must be >= 0 (minimum value)", path: []}
      #    ]}
  """

  @type validation_result :: {:ok, map()} | {:error, [violation()]}

  @type violation :: %{
          field: atom(),
          error: String.t(),
          path: [atom()]
        }

  @doc """
  Validates data against a contract.

  Returns `{:ok, data}` if validation passes, or `{:error, violations}` if it fails.

  ## Parameters

    * `module` - The module containing the contract
    * `contract_name` - The name of the contract to validate against
    * `data` - The data to validate (must be a map)

  ## Examples

      iex> defmodule TestContract do
      ...>   use Perimeter.Contract
      ...>   defcontract :simple do
      ...>     required :name, :string
      ...>   end
      ...> end
      iex> Perimeter.Validator.validate(TestContract, :simple, %{name: "Alice"})
      {:ok, %{name: "Alice"}}
  """
  @spec validate(module(), atom(), map()) :: validation_result()
  def validate(module, contract_name, data) when is_map(data) do
    case module.__contract__(contract_name) do
      nil ->
        {:error, [%{field: :_contract, error: "contract #{contract_name} not found", path: []}]}

      contract ->
        do_validate(contract.fields, data, [])
    end
  end

  def validate(_module, _contract_name, data) do
    {:error, [%{field: :_root, error: "expected map, got #{inspect(data)}", path: []}]}
  end

  # Validate all fields and collect violations
  defp do_validate(fields, data, path) do
    violations =
      Enum.reduce(fields, [], fn field, acc ->
        case validate_field(field, data, path) do
          :ok -> acc
          {:error, field_violations} -> field_violations ++ acc
        end
      end)

    case violations do
      [] -> {:ok, data}
      violations -> {:error, Enum.reverse(violations)}
    end
  end

  # Validate a single field
  defp validate_field(field, data, path) do
    case Map.fetch(data, field.name) do
      {:ok, value} ->
        # Field is present, validate type and constraints
        with :ok <- validate_type(field, value, path),
             :ok <- validate_constraints(field, value, path) do
          validate_nested(field, value, path)
        end

      :error ->
        # Field is missing
        if field.required do
          {:error, [%{field: field.name, error: "is required", path: path}]}
        else
          :ok
        end
    end
  end

  # Validate field type
  defp validate_type(field, value, path) do
    case check_type(field.type, value) do
      true ->
        :ok

      false ->
        expected = type_name(field.type)
        actual = value_type_name(value)
        {:error, [%{field: field.name, error: "expected #{expected}, got #{actual}", path: path}]}
    end
  end

  # Type checking
  defp check_type(:string, value), do: is_binary(value)
  defp check_type(:integer, value), do: is_integer(value)
  defp check_type(:float, value), do: is_float(value)
  defp check_type(:boolean, value), do: is_boolean(value)
  defp check_type(:atom, value), do: is_atom(value)
  defp check_type(:map, value), do: is_map(value)
  defp check_type(:list, value), do: is_list(value)
  defp check_type({:list, _item_type}, value), do: is_list(value)
  defp check_type(_, _), do: false

  # Type names for error messages
  defp type_name(:string), do: "string"
  defp type_name(:integer), do: "integer"
  defp type_name(:float), do: "float"
  defp type_name(:boolean), do: "boolean"
  defp type_name(:atom), do: "atom"
  defp type_name(:map), do: "map"
  defp type_name(:list), do: "list"
  defp type_name({:list, item_type}), do: "list of #{type_name(item_type)}"

  defp value_type_name(value) when is_binary(value), do: "string"
  defp value_type_name(value) when is_integer(value), do: "integer"
  defp value_type_name(value) when is_float(value), do: "float"
  defp value_type_name(value) when is_boolean(value), do: "boolean"
  defp value_type_name(value) when is_atom(value), do: "atom"
  defp value_type_name(value) when is_map(value), do: "map"
  defp value_type_name(value) when is_list(value), do: "list"
  defp value_type_name(_), do: "unknown"

  # Validate constraints
  defp validate_constraints(field, value, path) do
    violations =
      Enum.reduce(field.constraints, [], fn constraint, acc ->
        case validate_constraint(constraint, field.name, value, path) do
          :ok -> acc
          {:error, violation} -> [violation | acc]
        end
      end)

    case violations do
      [] -> :ok
      violations -> {:error, Enum.reverse(violations)}
    end
  end

  # Individual constraint validators
  defp validate_constraint({:format, regex}, field_name, value, path) when is_binary(value) do
    if Regex.match?(regex, value) do
      :ok
    else
      {:error, %{field: field_name, error: "does not match format", path: path}}
    end
  end

  defp validate_constraint({:min_length, min}, field_name, value, path) when is_binary(value) do
    if String.length(value) >= min do
      :ok
    else
      {:error,
       %{
         field: field_name,
         error: "must be at least #{min} characters (minimum length)",
         path: path
       }}
    end
  end

  defp validate_constraint({:max_length, max}, field_name, value, path) when is_binary(value) do
    if String.length(value) <= max do
      :ok
    else
      {:error,
       %{
         field: field_name,
         error: "must be at most #{max} characters (maximum length)",
         path: path
       }}
    end
  end

  defp validate_constraint({:min, min}, field_name, value, path) when is_number(value) do
    if value >= min do
      :ok
    else
      {:error, %{field: field_name, error: "must be >= #{min} (minimum value)", path: path}}
    end
  end

  defp validate_constraint({:max, max}, field_name, value, path) when is_number(value) do
    if value <= max do
      :ok
    else
      {:error, %{field: field_name, error: "must be <= #{max} (maximum value)", path: path}}
    end
  end

  defp validate_constraint({:in, allowed_values}, field_name, value, path) do
    if value in allowed_values do
      :ok
    else
      values_str = Enum.map_join(allowed_values, ", ", &inspect/1)
      {:error, %{field: field_name, error: "must be one of: #{values_str}", path: path}}
    end
  end

  # Skip constraints that don't apply to this value type
  defp validate_constraint(_constraint, _field_name, _value, _path), do: :ok

  # Validate nested fields (for maps) or list items
  defp validate_nested(%{type: :map, nested_fields: nested_fields, name: field_name}, value, path)
       when is_list(nested_fields) and is_map(value) do
    # Add current field to path for nested validation
    nested_path = path ++ [field_name]

    case do_validate(nested_fields, value, nested_path) do
      {:ok, _} -> :ok
      {:error, violations} -> {:error, violations}
    end
  end

  defp validate_nested(%{type: {:list, item_type}, name: field_name}, value, path)
       when is_list(value) do
    # Validate each item in the list
    violations =
      value
      |> Enum.with_index()
      |> Enum.reduce([], fn {item, _index}, acc ->
        if check_type(item_type, item) do
          acc
        else
          expected = type_name(item_type)
          actual = value_type_name(item)

          violation = %{
            field: field_name,
            error: "invalid list item: expected #{expected}, got #{actual}",
            path: path
          }

          [violation | acc]
        end
      end)

    case violations do
      [] -> :ok
      violations -> {:error, Enum.reverse(violations)}
    end
  end

  # No nested validation needed
  defp validate_nested(_field, _value, _path), do: :ok
end
