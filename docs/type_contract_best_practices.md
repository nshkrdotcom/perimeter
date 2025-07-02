# Type Contract Best Practices for Elixir

## Overview

This guide establishes best practices for defining and using type contracts in Elixir, focusing on avoiding common antipatterns while maintaining code clarity and performance. These practices build upon the "Defensive Boundary / Offensive Interior" pattern to create maintainable, type-safe systems.

## Contract Definition Best Practices

### 1. Prefer Explicit Over Implicit Contracts

**Good Practice**: Define contracts that clearly express intent

```elixir
defmodule UserContracts do
  use Jido.TypeContract
  
  # Explicit about what constitutes a valid user
  defcontract :user_registration do
    required :email, :string, format: ~r/^[^@]+@[^@]+$/
    required :password, :string, min_length: 8
    required :terms_accepted, :boolean, equals: true
    optional :name, :string, max_length: 100
    
    validate :password_complexity
  end
  
  defp password_complexity(%{password: password}) do
    if password =~ ~r/[A-Z]/ && password =~ ~r/[0-9]/ do
      :ok
    else
      {:error, %{field: :password, error: "must contain uppercase and number"}}
    end
  end
end
```

**Antipattern Avoided**: Non-Assertive Pattern Matching

```elixir
# Bad: Accepts any map without validation
def register_user(params) do
  # Hoping the right fields exist...
  %{email: params["email"], password: params["password"]}
end

# Good: Explicit contract enforcement
@guard input: :user_registration
def register_user(params) do
  # We know these fields exist and are valid
  %{email: email, password: password} = params
end
```

### 2. Use Composition for Complex Contracts

**Good Practice**: Build complex contracts from simple, reusable components

```elixir
defmodule SharedContracts do
  use Jido.TypeContract
  
  # Basic building blocks
  defcontract :email do
    required :email, :string, format: ~r/@/
  end
  
  defcontract :timestamps do
    required :created_at, :datetime
    required :updated_at, :datetime
  end
  
  defcontract :pagination do
    optional :page, :integer, min: 1, default: 1
    optional :per_page, :integer, min: 1, max: 100, default: 20
  end
  
  # Composed contract
  defcontract :user_query do
    compose [:email, :pagination]
    optional :include_deleted, :boolean, default: false
  end
end
```

### 3. Avoid Over-Constraining Contracts

**Good Practice**: Balance strictness with flexibility

```elixir
defmodule FlexibleContracts do
  use Jido.TypeContract
  
  # Too rigid - couples to specific implementation
  defcontract :overly_strict_address do
    required :street_number, :integer
    required :street_name, :string
    required :city, :string
    required :state, :string, length: 2
    required :zip, :string, format: ~r/^\d{5}$/
  end
  
  # Better - allows for international addresses
  defcontract :flexible_address do
    required :line1, :string, min_length: 1
    optional :line2, :string
    required :city, :string, min_length: 1
    required :country_code, :string, length: 2
    optional :postal_code, :string  # Format varies by country
    optional :state_province, :string
    
    validate :country_specific_validation
  end
end
```

### 4. Use Semantic Field Names

**Good Practice**: Choose field names that express domain concepts

```elixir
defmodule DomainContracts do
  use Jido.TypeContract
  
  # Poor naming
  defcontract :bad_transaction do
    required :amt, :decimal
    required :dt, :datetime
    required :st, :integer
  end
  
  # Clear, semantic naming
  defcontract :transaction do
    required :amount_cents, :integer, min: 0
    required :occurred_at, :datetime
    required :status, :atom, in: [:pending, :completed, :failed]
    required :currency, :string, length: 3
  end
end
```

## Contract Validation Patterns

### 1. Fail Fast with Clear Messages

**Good Practice**: Provide actionable error messages

```elixir
defmodule ValidationPatterns do
  use Jido.TypeContract
  
  defcontract :order do
    required :items, {:list, :order_item}, min_items: 1
    required :shipping_address, :map
    
    validate :total_within_limits
  end
  
  defcontract :order_item do
    required :product_id, :string
    required :quantity, :integer, min: 1
    required :unit_price_cents, :integer, min: 0
  end
  
  defp total_within_limits(%{items: items}) do
    total = Enum.sum(for item <- items, do: item.quantity * item.unit_price_cents)
    
    cond do
      total == 0 ->
        {:error, %{
          field: :items,
          error: "order total cannot be zero",
          hint: "Ensure items have valid prices and quantities"
        }}
      
      total > 1_000_000_00 ->
        {:error, %{
          field: :items,
          error: "order total exceeds maximum ($1,000,000)",
          value: total,
          max: 1_000_000_00
        }}
      
      true ->
        :ok
    end
  end
end
```

### 2. Progressive Contract Validation

**Good Practice**: Validate in stages for better performance and error reporting

```elixir
defmodule ProgressiveValidation do
  use Jido.TypeContract
  
  # Stage 1: Basic structure validation
  defcontract :import_file_basic do
    required :filename, :string, format: ~r/\.csv$/
    required :size_bytes, :integer, max: 100_000_000  # 100MB
  end
  
  # Stage 2: Content validation (after basic passes)
  defcontract :import_file_content do
    required :headers, {:list, :string}, min_items: 1
    required :row_count, :integer, min: 1
    required :encoding, :atom, in: [:utf8, :utf16, :latin1]
  end
  
  # Use progressively
  def validate_import(file_info) do
    with {:ok, _} <- validate_contract(:import_file_basic, file_info),
         {:ok, content} <- read_file_headers(file_info),
         {:ok, _} <- validate_contract(:import_file_content, content) do
      {:ok, :valid}
    end
  end
end
```

### 3. Context-Aware Validation

**Good Practice**: Contracts that adapt based on context

```elixir
defmodule ContextualContracts do
  use Jido.TypeContract
  
  defcontract :user_update do
    optional :email, :string, format: ~r/@/
    optional :name, :string
    optional :role, :atom
    
    # Different validation based on who's updating
    validate {:role_change_allowed, :context}
  end
  
  defp role_change_allowed(params, context) do
    case params[:role] do
      nil -> 
        :ok
      new_role ->
        if context.current_user.role == :admin do
          :ok
        else
          {:error, %{
            field: :role,
            error: "only admins can change roles",
            current_user_role: context.current_user.role
          }}
        end
    end
  end
end
```

## Performance Best Practices

### 1. Compile-Time Contract Optimization

**Good Practice**: Move validation logic to compile time when possible

```elixir
defmodule OptimizedContracts do
  use Jido.TypeContract
  
  # Compile-time constant validation
  @valid_currencies ~w(USD EUR GBP JPY CNY)
  @valid_statuses [:draft, :published, :archived]
  
  defcontract :product do
    required :price_cents, :integer, min: 0
    required :currency, :string, in: @valid_currencies
    required :status, :atom, in: @valid_statuses
  end
  
  # Generate optimized validators at compile time
  for currency <- @valid_currencies do
    def valid_currency?(unquote(currency)), do: true
  end
  def valid_currency?(_), do: false
end
```

### 2. Lazy Validation for Large Structures

**Good Practice**: Validate only what's needed

```elixir
defmodule LazyValidation do
  use Jido.TypeContract
  
  defcontract :large_dataset do
    required :metadata, :map
    required :data, {:lazy, :validate_data_chunk}
    
    validate :check_data_format
  end
  
  # Only validate accessed portions
  def validate_data_chunk(data, accessed_indices) do
    accessed_indices
    |> Enum.map(&Enum.at(data, &1))
    |> Enum.all?(&valid_data_point?/1)
  end
end
```

### 3. Cached Contract Validation

**Good Practice**: Cache validation results for immutable data

```elixir
defmodule CachedValidation do
  use Jido.TypeContract
  
  @ttl_seconds 300  # 5 minutes
  
  defcontract :api_response do
    required :status, :integer, in: 200..299
    required :body, :map
    required :headers, :map
    
    validate {:check_rate_limits, :cached}
  end
  
  defp check_rate_limits(params, :cached) do
    cache_key = :crypto.hash(:sha256, :erlang.term_to_binary(params))
    
    case :ets.lookup(:validation_cache, cache_key) do
      [{_, result, expiry}] when expiry > System.monotonic_time() ->
        result
      _ ->
        result = do_check_rate_limits(params)
        expiry = System.monotonic_time() + @ttl_seconds
        :ets.insert(:validation_cache, {cache_key, result, expiry})
        result
    end
  end
end
```

## Integration Best Practices

### 1. Contract Documentation

**Good Practice**: Self-documenting contracts

```elixir
defmodule DocumentedContracts do
  use Jido.TypeContract
  
  @doc """
  Contract for user profile updates.
  
  ## Required Fields
  - None (all fields optional for updates)
  
  ## Optional Fields
  - `:bio` - User biography (max 500 chars)
  - `:avatar_url` - Valid URL to avatar image
  - `:preferences` - User preference map
  
  ## Validations
  - Bio must not contain profanity
  - Avatar URL must be HTTPS
  - At least one field must be present
  """
  defcontract :profile_update do
    optional :bio, :string, max_length: 500
    optional :avatar_url, :string, format: ~r/^https:\/\//
    optional :preferences, :map do
      optional :theme, :atom, in: [:light, :dark, :auto]
      optional :notifications, :boolean
    end
    
    validate :at_least_one_field
    validate :bio_appropriate
  end
end
```

### 2. Contract Testing Helpers

**Good Practice**: Provide test utilities for contracts

```elixir
defmodule ContractTestHelpers do
  defmacro assert_contract_valid(contract, data) do
    quote do
      case validate_contract(unquote(contract), unquote(data)) do
        {:ok, _} -> 
          :ok
        {:error, violations} ->
          flunk """
          Contract validation failed:
          #{format_violations(violations)}
          
          Data provided:
          #{inspect(unquote(data), pretty: true)}
          """
      end
    end
  end
  
  defmacro assert_contract_invalid(contract, data, expected_field) do
    quote do
      case validate_contract(unquote(contract), unquote(data)) do
        {:error, violations} ->
          violated_fields = Enum.map(violations, & &1.field)
          assert unquote(expected_field) in violated_fields
        {:ok, _} ->
          flunk "Expected contract validation to fail for field: #{unquote(expected_field)}"
      end
    end
  end
end
```

### 3. Contract Versioning

**Good Practice**: Support contract evolution

```elixir
defmodule VersionedContracts do
  use Jido.TypeContract
  
  # Current version
  defcontract :user_v2 do
    required :id, :string
    required :email, :string
    required :profile, :map
    optional :preferences, :map
  end
  
  # Legacy support
  defcontract :user_v1 do
    required :id, :string
    required :email, :string
    optional :name, :string
  end
  
  # Migration helper
  def migrate_user_v1_to_v2(v1_user) do
    %{
      id: v1_user.id,
      email: v1_user.email,
      profile: %{name: v1_user[:name] || ""},
      preferences: %{}
    }
  end
  
  # Auto-upgrade in validation
  def validate_user(data) do
    case validate_contract(:user_v2, data) do
      {:ok, _} = result -> 
        result
      {:error, _} ->
        # Try v1 and migrate
        with {:ok, v1_data} <- validate_contract(:user_v1, data) do
          v2_data = migrate_user_v1_to_v2(v1_data)
          {:ok, v2_data}
        end
    end
  end
end
```

## Common Pitfalls and Solutions

### 1. Over-Validation

**Pitfall**: Validating the same data multiple times

```elixir
# Bad: Redundant validation
def process_order(params) do
  with {:ok, _} <- validate_contract(:order, params),
       {:ok, _} <- validate_items(params.items),  # Items already validated!
       {:ok, _} <- validate_shipping(params.shipping) do  # Shipping already validated!
    # ...
  end
end

# Good: Trust validated data
def process_order(params) do
  with {:ok, validated} <- validate_contract(:order, params) do
    # Trust that validated.items and validated.shipping are valid
    process_validated_order(validated)
  end
end
```

### 2. Contract Sprawl

**Pitfall**: Too many similar contracts

```elixir
# Bad: Separate contract for each minor variation
defcontract :user_create
defcontract :user_update  
defcontract :user_admin_create
defcontract :user_admin_update
defcontract :user_import

# Good: Parameterized contracts
defcontract :user, mode do
  case mode do
    :create ->
      required :email, :string
      required :password, :string
    :update ->
      optional :email, :string
      optional :password, :string
    :import ->
      required :email, :string
      optional :external_id, :string
  end
  
  # Shared validations
  validate :email_format
end
```

### 3. Mixing Business Logic with Validation

**Pitfall**: Contracts that do too much

```elixir
# Bad: Business logic in contract
defcontract :order do
  required :items, {:list, :item}
  
  validate :calculate_tax  # Don't do this!
  validate :check_inventory  # Don't do this!
end

# Good: Pure validation
defcontract :order do
  required :items, {:list, :item}, min_items: 1
  required :shipping_country, :string, length: 2
  
  validate :items_have_valid_products
end

# Business logic separate
def process_order(validated_order) do
  with {:ok, tax} <- calculate_tax(validated_order),
       {:ok, _} <- check_inventory(validated_order.items) do
    # ...
  end
end
```

## Summary of Best Practices

1. **Be Explicit**: Define clear contracts that express intent
2. **Compose, Don't Repeat**: Build complex contracts from simple ones
3. **Fail Fast**: Validate at boundaries with clear error messages
4. **Trust the Interior**: Don't re-validate already validated data
5. **Optimize Wisely**: Use compile-time optimization and caching
6. **Document Well**: Self-documenting contracts with examples
7. **Test Thoroughly**: Provide test helpers and property tests
8. **Version Carefully**: Support contract evolution
9. **Keep It Pure**: Separate validation from business logic
10. **Avoid Sprawl**: Use parameterized contracts for variations

By following these practices, you create a type-safe system that leverages Elixir's strengths while avoiding common pitfalls and antipatterns.