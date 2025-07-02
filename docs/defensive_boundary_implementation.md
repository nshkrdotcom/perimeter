# Defensive Boundary Implementation Guide

## Introduction

This guide provides practical implementation patterns for the "Defensive Boundary / Offensive Interior" approach in Elixir applications. It shows how to build robust type boundaries while avoiding common antipatterns and maintaining Elixir's idiomatic style.

## Core Implementation Components

### 1. Boundary Guard Module

The foundation of defensive boundaries is a robust guard system that validates data at entry points:

```elixir
defmodule Jido.BoundaryGuard do
  @moduledoc """
  Provides compile-time and runtime boundary enforcement for type contracts.
  Implements the three-zone model: Defensive Perimeter, Transition Layer, and Offensive Interior.
  """
  
  defmacro __using__(opts) do
    enforcement_level = Keyword.get(opts, :enforcement, :strict)
    
    quote do
      import Jido.BoundaryGuard
      Module.register_attribute(__MODULE__, :boundary_contracts, accumulate: true)
      Module.register_attribute(__MODULE__, :enforcement_level, persist: true)
      @enforcement_level unquote(enforcement_level)
      @before_compile Jido.BoundaryGuard
    end
  end
  
  defmacro __before_compile__(env) do
    contracts = Module.get_attribute(env.module, :boundary_contracts)
    
    # Generate runtime validation functions
    validations = Enum.map(contracts, fn {function, contract} ->
      generate_validation(function, contract)
    end)
    
    quote do
      unquote_splicing(validations)
    end
  end
  
  defmacro guard(opts) do
    quote do
      @boundary_contracts {unquote(opts[:function]), unquote(opts)}
    end
  end
  
  defp generate_validation(function, opts) do
    input_contract = opts[:input]
    output_contract = opts[:output]
    
    quote do
      defoverridable [{unquote(function), 2}]
      
      def unquote(function)(params, context) do
        # Defensive Perimeter: Validate inputs
        with {:ok, validated_params} <- validate_input(unquote(input_contract), params),
             {:ok, validated_context} <- validate_context(context) do
          
          # Transition Layer: Transform and normalize
          normalized_params = normalize_params(validated_params)
          
          # Offensive Interior: Execute with validated data
          result = super(normalized_params, validated_context)
          
          # Exit Boundary: Validate output
          validate_and_wrap_output(unquote(output_contract), result)
        else
          {:error, violations} ->
            handle_boundary_violation(violations, @enforcement_level)
        end
      end
    end
  end
end
```

### 2. Contract Validation Engine

Implement efficient contract validation that avoids defensive programming:

```elixir
defmodule Jido.ContractValidator do
  @moduledoc """
  Validates data against contracts using assertive pattern matching.
  Avoids the Non-Assertive Pattern Matching antipattern.
  """
  
  def validate(contract_module, contract_name, data) do
    contract = contract_module.__contract__(contract_name)
    
    # Build validation pipeline at compile time for efficiency
    validators = build_validators(contract)
    
    # Execute validation pipeline
    validators
    |> Enum.reduce_while({:ok, data}, fn validator, {:ok, acc} ->
      case validator.(acc) do
        {:ok, result} -> {:cont, {:ok, result}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end
  
  defp build_validators(contract) do
    contract
    |> Enum.map(&field_validator/1)
    |> add_custom_validators(contract[:validate])
  end
  
  defp field_validator({:required, field, type, opts}) do
    fn data ->
      # Assertive pattern matching - we expect the field to exist
      case Map.fetch(data, field) do
        {:ok, value} ->
          validate_field_type(field, value, type, opts)
        :error ->
          {:error, %{field: field, error: "is required"}}
      end
    end
  end
  
  defp field_validator({:optional, field, type, opts}) do
    fn data ->
      # Optional fields use dynamic access pattern
      case data[field] do
        nil -> {:ok, data}
        value -> validate_field_type(field, value, type, opts)
      end
    end
  end
  
  defp validate_field_type(field, value, type, opts) do
    # Type-specific validation with clear pattern matching
    case type do
      :string when is_binary(value) ->
        validate_string_constraints(field, value, opts)
      :integer when is_integer(value) ->
        validate_integer_constraints(field, value, opts)
      :atom when is_atom(value) ->
        validate_atom_constraints(field, value, opts)
      {:list, item_type} when is_list(value) ->
        validate_list_items(field, value, item_type, opts)
      _ ->
        {:error, %{field: field, error: "invalid type"}}
    end
  end
end
```

### 3. Transition Layer Implementation

The transition layer handles data normalization between boundaries and interior:

```elixir
defmodule Jido.TransitionLayer do
  @moduledoc """
  Handles type transformation and normalization at boundary crossings.
  Ensures data is in the correct shape for interior processing.
  """
  
  def normalize_params(params) when is_map(params) do
    params
    |> convert_string_keys_to_atoms()
    |> normalize_nested_structures()
    |> apply_default_values()
  end
  
  # Avoid dynamic atom creation antipattern
  defp convert_string_keys_to_atoms(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) ->
        # Only convert to existing atoms
        case safe_to_existing_atom(key) do
          {:ok, atom} -> {atom, value}
          :error -> {key, value}  # Keep as string if atom doesn't exist
        end
      {key, value} ->
        {key, value}
    end)
  end
  
  defp safe_to_existing_atom(string) do
    {:ok, String.to_existing_atom(string)}
  rescue
    ArgumentError -> :error
  end
  
  defp normalize_nested_structures(map) do
    Map.new(map, fn
      {key, value} when is_map(value) ->
        {key, normalize_nested_structures(value)}
      {key, value} when is_list(value) ->
        {key, Enum.map(value, &normalize_if_map/1)}
      {key, value} ->
        {key, value}
    end)
  end
  
  defp normalize_if_map(value) when is_map(value), do: normalize_nested_structures(value)
  defp normalize_if_map(value), do: value
end
```

### 4. Runtime Enforcement Configuration

Implement flexible enforcement levels for different environments:

```elixir
defmodule Jido.Runtime.Enforcement do
  @moduledoc """
  Configures and manages runtime type enforcement levels.
  Allows different strictness in development vs production.
  """
  
  use GenServer
  
  @enforcement_levels [:none, :log, :warn, :strict]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    default_level = Keyword.get(opts, :default_level, :warn)
    module_overrides = Keyword.get(opts, :module_overrides, %{})
    
    state = %{
      default_level: default_level,
      module_levels: module_overrides,
      violations: :queue.new(),
      telemetry_enabled: Keyword.get(opts, :telemetry, true)
    }
    
    {:ok, state}
  end
  
  def set_level(level) when level in @enforcement_levels do
    GenServer.call(__MODULE__, {:set_default_level, level})
  end
  
  def set_module_level(module, level) when level in @enforcement_levels do
    GenServer.call(__MODULE__, {:set_module_level, module, level})
  end
  
  def handle_violation(violation, module) do
    GenServer.call(__MODULE__, {:handle_violation, violation, module})
  end
  
  def handle_call({:handle_violation, violation, module}, _from, state) do
    level = get_enforcement_level(module, state)
    
    # Emit telemetry event if enabled
    if state.telemetry_enabled do
      :telemetry.execute(
        [:jido, :boundary, :violation],
        %{count: 1},
        %{module: module, level: level}
      )
    end
    
    response = case level do
      :none -> 
        :ok
      :log -> 
        log_violation(violation)
        :ok
      :warn ->
        warn_violation(violation)
        :ok
      :strict ->
        {:error, format_violation_error(violation)}
    end
    
    # Store violation for reporting
    new_state = %{state | violations: :queue.in({module, violation}, state.violations)}
    
    {:reply, response, new_state}
  end
  
  defp get_enforcement_level(module, state) do
    Map.get(state.module_levels, module, state.default_level)
  end
end
```

### 5. Practical Action Implementation

Here's how to implement an action with proper boundary enforcement:

```elixir
defmodule MyApp.Actions.CreateUser do
  use Jido.Action
  use Jido.BoundaryGuard, enforcement: :strict
  use Jido.TypeContract
  
  # Define input contract
  defcontract :input do
    required :name, :string, min_length: 1, max_length: 100
    required :email, :string, format: ~r/@/
    optional :age, :integer, min: 18, max: 150
    optional :metadata, :map do
      optional :source, :string
      optional :referrer, :string
    end
    
    validate :email_unique
  end
  
  # Define output contract
  defcontract :output do
    required :id, :string
    required :user, MyApp.User
    required :created_at, :datetime
  end
  
  @impl true
  @guard function: :run, input: :input, output: :output
  def run(params, context) do
    # Interior: We can trust params are validated
    %{name: name, email: email} = params
    age = params[:age]  # Optional field access
    
    # Business logic with full confidence in data structure
    with {:ok, user} <- create_user_record(name, email, age),
         {:ok, _} <- send_welcome_email(user),
         {:ok, _} <- emit_user_created_event(user) do
      
      # Output will be validated by boundary guard
      {:ok, %{
        id: user.id,
        user: user,
        created_at: user.inserted_at
      }}
    end
  end
  
  # Custom validation function
  defp email_unique(params) do
    case MyApp.Repo.get_by(User, email: params.email) do
      nil -> {:ok, params}
      _user -> {:error, %{field: :email, error: "has already been taken"}}
    end
  end
  
  # Interior functions work with validated data
  defp create_user_record(name, email, age) do
    %User{}
    |> User.changeset(%{name: name, email: email, age: age})
    |> MyApp.Repo.insert()
  end
end
```

### 6. Agent with Boundary Protection

Implement an agent with proper state boundaries:

```elixir
defmodule MyApp.Agents.DataProcessor do
  use Jido.Agent
  use Jido.BoundaryGuard
  use Jido.TypeContract
  
  # State contract ensures state integrity
  defcontract :state do
    required :status, :atom, in: [:idle, :processing, :complete, :error]
    required :items_processed, :integer, min: 0
    required :items_total, :integer, min: 0
    optional :current_item, :map
    optional :errors, {:list, :map}
    
    validate :items_processed_not_greater_than_total
  end
  
  # Instruction contract for planning
  defcontract :instruction do
    required :action, :atom
    required :params, :map
    optional :timeout, :integer, min: 0
  end
  
  def initial_state do
    %{
      status: :idle,
      items_processed: 0,
      items_total: 0,
      errors: []
    }
  end
  
  @impl true
  @guard function: :on_before_plan, input: :instruction
  def on_before_plan(agent, instruction, params) do
    # Validate instruction at boundary
    {:ok, agent}
  end
  
  @impl true
  @guard function: :on_after_run, input: :state
  def on_after_run(agent) do
    # State validation happens automatically via guard
    maybe_transition_to_complete(agent)
  end
  
  # Custom validation
  defp items_processed_not_greater_than_total(%{items_processed: processed, items_total: total}) do
    if processed <= total do
      {:ok, true}
    else
      {:error, %{field: :items_processed, error: "cannot exceed items_total"}}
    end
  end
  
  # Interior logic with validated state
  defp maybe_transition_to_complete(agent) do
    if agent.state.items_processed == agent.state.items_total do
      {:ok, %{agent | state: %{agent.state | status: :complete}}}
    else
      {:ok, agent}
    end
  end
end
```

### 7. Error Boundary Handling

Implement proper error handling at boundaries:

```elixir
defmodule Jido.ErrorBoundary do
  @moduledoc """
  Handles errors at type boundaries with proper context and recovery.
  """
  
  def handle_boundary_violation(violations, enforcement_level) do
    error = %Jido.Error{
      type: :validation_error,
      message: "Contract violation at boundary",
      details: %{
        violations: format_violations(violations),
        enforcement_level: enforcement_level
      },
      stacktrace: get_clean_stacktrace()
    }
    
    case enforcement_level do
      :strict -> {:error, error}
      :warn -> 
        Logger.warning("Boundary violation: #{inspect(error)}")
        :ok
      :log ->
        Logger.debug("Boundary violation: #{inspect(error)}")
        :ok
      :none ->
        :ok
    end
  end
  
  def format_violations(violations) when is_list(violations) do
    Enum.map(violations, &format_single_violation/1)
  end
  
  defp format_single_violation(%{field: field, error: error, path: path}) do
    field_path = Enum.join(path ++ [field], ".")
    "#{field_path} #{error}"
  end
  
  defp get_clean_stacktrace do
    self()
    |> Process.info(:current_stacktrace)
    |> elem(1)
    |> Enum.drop(3)  # Remove internal frames
    |> Enum.take(10)  # Limit depth
  end
end
```

## Integration Patterns

### With Phoenix Controllers

```elixir
defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller
  use Jido.BoundaryGuard
  
  defcontract :create_params do
    required :user, :map do
      required :name, :string
      required :email, :string
    end
  end
  
  @guard function: :create, input: :create_params
  def create(conn, params) do
    # Params are validated at boundary
    case MyApp.Actions.CreateUser.run(params.user, build_context(conn)) do
      {:ok, result} ->
        conn
        |> put_status(:created)
        |> render("show.json", user: result.user)
      {:error, error} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render("error.json", error: error)
    end
  end
end
```

### With GenServer

```elixir
defmodule MyApp.ProcessingServer do
  use GenServer
  use Jido.BoundaryGuard
  
  defcontract :process_request do
    required :type, :atom, in: [:sync, :async]
    required :data, :map
    optional :callback, :function
  end
  
  def process(server, request) do
    GenServer.call(server, {:process, request})
  end
  
  @guard function: :handle_call, input: :process_request
  def handle_call({:process, request}, from, state) do
    # Request validated at boundary
    result = do_process(request.type, request.data)
    {:reply, result, state}
  end
end
```

## Performance Optimization

### 1. Compile-Time Contract Resolution

```elixir
defmodule Jido.ContractCompiler do
  @moduledoc """
  Compiles contracts into optimized validation functions at compile time.
  """
  
  defmacro compile_contract(contract) do
    # Generate optimized validation code
    validators = build_validator_ast(contract)
    
    quote do
      def __compiled_validator__ do
        fn data ->
          unquote(validators)
        end
      end
    end
  end
end
```

### 2. Validation Caching

```elixir
defmodule Jido.ValidationCache do
  @moduledoc """
  Caches validation results for frequently validated data structures.
  """
  
  use GenServer
  
  def validate_with_cache(contract, data) do
    cache_key = :erlang.phash2({contract, data})
    
    case :ets.lookup(:validation_cache, cache_key) do
      [{^cache_key, result}] -> 
        hit_telemetry()
        result
      [] ->
        miss_telemetry()
        result = perform_validation(contract, data)
        :ets.insert(:validation_cache, {cache_key, result})
        result
    end
  end
end
```

## Testing Boundaries

### Contract Testing

```elixir
defmodule MyApp.Actions.CreateUserTest do
  use ExUnit.Case
  use Jido.ContractTesting
  
  describe "boundary contracts" do
    contract_test MyApp.Actions.CreateUser do
      valid_inputs [
        %{name: "John", email: "john@example.com"},
        %{name: "Jane", email: "jane@example.com", age: 25}
      ]
      
      invalid_inputs [
        %{name: "", email: "john@example.com"},  # Empty name
        %{name: "John", email: "invalid"},       # Invalid email
        %{name: "John"},                         # Missing email
        %{name: "John", email: "j@e.com", age: 17}  # Age too low
      ]
      
      valid_outputs [
        %{id: "123", user: %User{}, created_at: DateTime.utc_now()}
      ]
      
      invalid_outputs [
        %{id: 123, user: %User{}, created_at: DateTime.utc_now()},  # id not string
        %{user: %User{}, created_at: DateTime.utc_now()},           # missing id
        %{id: "123", user: nil, created_at: DateTime.utc_now()}     # nil user
      ]
    end
  end
end
```

## Conclusion

The Defensive Boundary pattern provides a practical approach to type safety in Elixir that:

1. **Validates assertively** at system boundaries
2. **Trusts validated data** in the interior
3. **Fails fast** with clear error messages
4. **Preserves Elixir idioms** and patterns
5. **Enables metaprogramming** within safe boundaries

By implementing these patterns, you create systems that are both flexible and robust, avoiding common antipatterns while embracing Elixir's strengths.