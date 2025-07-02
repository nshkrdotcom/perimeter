# Jido Type Enforcement Library Specification

## Overview

The Jido Type Enforcement Library provides a practical, lightweight system for runtime type validation in Elixir applications. It implements the "Defensive Boundary / Offensive Interior" pattern, allowing unrestricted metaprogramming within type-safe boundaries.

## Core Modules

### 1. `Jido.TypeContract`

**Purpose**: Define and register type contracts at compile time.

```elixir
defmodule Jido.TypeContract do
  @moduledoc """
  Provides macros for defining type contracts that are enforced at module boundaries.
  Contracts are compiled into efficient validation functions.
  """
  
  @type contract_name :: atom()
  @type field_spec :: {atom(), field_type(), keyword()}
  @type field_type :: :string | :atom | :integer | :float | :decimal | :boolean | 
                      :date | :datetime | :map | :list | {:list, field_type()} |
                      :any | module()
  
  @doc """
  Defines a type contract with field specifications.
  
  ## Examples
  
      defcontract :user_input do
        required :name, :string, min_length: 1, max_length: 100
        required :age, :integer, min: 0, max: 150
        optional :email, :string, format: ~r/@/
        
        optional :address, :map do
          required :street, :string
          required :city, :string
          optional :postal_code, :string, format: ~r/^\d{5}$/
        end
        
        validate :custom_validation
      end
  """
  defmacro defcontract(name, do: block)
  
  @doc """
  Defines a required field in a contract.
  """
  defmacro required(field_name, field_type, opts \\ [])
  
  @doc """
  Defines an optional field in a contract.
  """
  defmacro optional(field_name, field_type, opts \\ [])
  
  @doc """
  Adds a custom validation function to the contract.
  """
  defmacro validate(function_name)
  
  @doc """
  Composes multiple contracts together.
  """
  defmacro compose(contract_names)
end
```

### 2. `Jido.BoundaryGuard`

**Purpose**: Enforce contracts at function boundaries with minimal overhead.

```elixir
defmodule Jido.BoundaryGuard do
  @moduledoc """
  Provides boundary enforcement for type contracts with configurable
  validation levels and detailed error reporting.
  """
  
  @type validation_result :: {:ok, term()} | {:error, violations()}
  @type violations :: [violation()]
  @type violation :: %{
    field: atom(),
    value: term(),
    error: String.t(),
    path: [atom()]
  }
  
  @doc """
  Guards a function boundary with input/output contracts.
  
  ## Options
  
  - `:input` - Input contract name
  - `:output` - Output contract name  
  - `:on_violation` - :error | :warn | :log | :ignore
  - `:transform` - Function to transform input before validation
  
  ## Example
  
      @guard input: :user_input, output: :user_result
      def create_user(params, context) do
        # Implementation
      end
  """
  defmacro guard(opts \\ [])
  
  @doc """
  Validates data against a contract.
  """
  @spec validate(module(), contract_name :: atom(), data :: map()) :: validation_result()
  def validate(module, contract_name, data)
  
  @doc """
  Validates and transforms data in a single pass.
  """
  @spec validate_and_transform(module(), contract_name :: atom(), data :: map()) :: 
    {:ok, transformed :: map()} | {:error, violations()}
  def validate_and_transform(module, contract_name, data)
  
  @doc """
  Returns a human-readable error message for violations.
  """
  @spec format_violations(violations()) :: String.t()
  def format_violations(violations)
end
```

### 3. `Jido.TypeShape`

**Purpose**: Define reusable, composable type shapes.

```elixir
defmodule Jido.TypeShape do
  @moduledoc """
  Provides a way to define reusable type shapes that can be
  composed and validated efficiently.
  """
  
  @type t :: %__MODULE__{
    name: atom(),
    fields: map(),
    validators: [validator()],
    transformers: [transformer()],
    metadata: map()
  }
  
  @type validator :: (map() -> {:ok, map()} | {:error, String.t()})
  @type transformer :: (map() -> map())
  
  @doc """
  Creates a new type shape.
  
  ## Example
  
      address_shape = shape(:address,
        street: [type: :string, required: true],
        city: [type: :string, required: true],
        postal_code: [type: :string, format: ~r/^\d{5}$/]
      )
  """
  @spec shape(atom(), keyword()) :: t()
  def shape(name, fields)
  
  @doc """
  Adds a validator to a shape.
  """
  @spec add_validator(t(), validator()) :: t()
  def add_validator(shape, validator)
  
  @doc """
  Adds a transformer to a shape.
  """  
  @spec add_transformer(t(), transformer()) :: t()
  def add_transformer(shape, transformer)
  
  @doc """
  Composes multiple shapes into one.
  """
  @spec compose([t()]) :: t()
  def compose(shapes)
  
  @doc """
  Validates data against a shape.
  """
  @spec validate(t(), map()) :: {:ok, map()} | {:error, violations()}
  def validate(shape, data)
end
```

### 4. `Jido.Runtime.TypeValidator`

**Purpose**: High-performance runtime validation with caching.

```elixir
defmodule Jido.Runtime.TypeValidator do
  @moduledoc """
  GenServer that provides cached, optimized runtime type validation.
  Builds validation paths at startup for maximum performance.
  """
  
  use GenServer
  
  @type validation_stats :: %{
    total_validations: non_neg_integer(),
    cache_hits: non_neg_integer(),
    cache_misses: non_neg_integer(),
    average_validation_time: float()
  }
  
  @doc """
  Starts the type validator with options.
  
  ## Options
  
  - `:cache_size` - Maximum number of cached validations (default: 1000)
  - `:ttl` - Cache TTL in milliseconds (default: :infinity)
  - `:preload` - List of {module, contract} to preload
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ [])
  
  @doc """
  Validates data against a contract with caching.
  """
  @spec validate(module(), atom(), map()) :: {:ok, map()} | {:error, violations()}
  def validate(module, contract_name, data)
  
  @doc """
  Validates asynchronously for non-blocking validation.
  """
  @spec validate_async(module(), atom(), map()) :: Task.t()
  def validate_async(module, contract_name, data)
  
  @doc """
  Returns validation statistics.
  """
  @spec stats() :: validation_stats()
  def stats()
  
  @doc """
  Clears the validation cache.
  """
  @spec clear_cache() :: :ok
  def clear_cache()
end
```

### 5. `Jido.Dev.TypeChecker`

**Purpose**: Enhanced development-time type checking.

```elixir
defmodule Jido.Dev.TypeChecker do
  @moduledoc """
  Development-time type checker that provides detailed analysis
  and reporting of type violations.
  """
  
  @type check_result :: %{
    module: module(),
    violations: [violation()],
    warnings: [warning()],
    suggestions: [suggestion()]
  }
  
  @type violation :: %{type: atom(), message: String.t(), location: location()}
  @type warning :: %{type: atom(), message: String.t(), location: location()}
  @type suggestion :: %{type: atom(), message: String.t(), fix: String.t()}
  @type location :: {file :: String.t(), line :: pos_integer()}
  
  @doc """
  Enables type checking for a module in development.
  
  ## Example
  
      defmodule MyModule do
        use Jido.Dev.TypeChecker, strict: true
      end
  """
  defmacro __using__(opts)
  
  @doc """
  Analyzes a module for type violations.
  """
  @spec analyze(module()) :: check_result()
  def analyze(module)
  
  @doc """
  Analyzes all modules in an application.
  """
  @spec analyze_app(atom()) :: [check_result()]
  def analyze_app(app_name)
  
  @doc """
  Generates a type safety report.
  """
  @spec generate_report([check_result()]) :: String.t()
  def generate_report(results)
end
```

### 6. `Jido.TypeEnforcement`

**Purpose**: Configure and control type enforcement levels.

```elixir
defmodule Jido.TypeEnforcement do
  @moduledoc """
  Provides configuration and control over type enforcement levels
  at runtime with fine-grained control per module or globally.
  """
  
  @type level :: :none | :log | :warn | :strict
  @type config :: %{
    default_level: level(),
    module_levels: %{module() => level()},
    reporting: reporting_config()
  }
  @type reporting_config :: %{
    log_violations: boolean(),
    telemetry_events: boolean(),
    error_aggregation: boolean()
  }
  
  @doc """
  Sets the global enforcement level.
  """
  @spec set_level(level()) :: :ok
  def set_level(level)
  
  @doc """
  Sets the enforcement level for a specific module.
  """
  @spec set_module_level(module(), level()) :: :ok
  def set_module_level(module, level)
  
  @doc """
  Temporarily enforces a level for a block of code.
  
  ## Example
  
      enforce :strict do
        MyModule.dangerous_operation(params)
      end
  """
  defmacro enforce(level, do: block)
  
  @doc """
  Gets the current enforcement configuration.
  """
  @spec get_config() :: config()
  def get_config()
  
  @doc """
  Resets all enforcement to defaults.
  """
  @spec reset() :: :ok
  def reset()
end
```

## Integration Examples

### With Actions

```elixir
defmodule MyApp.Actions.CreateUser do
  use Jido.Action
  use Jido.TypeContract
  
  defcontract :input do
    required :name, :string, min_length: 1
    required :email, :string, format: ~r/@/
    optional :age, :integer, min: 18
  end
  
  defcontract :output do
    required :id, :string
    required :created_at, :datetime
    required :user, MyApp.User
  end
  
  @impl true
  @guard input: :input, output: :output
  def run(params, context) do
    # Type-safe interior
    user = MyApp.create_user!(params)
    {:ok, %{id: user.id, created_at: user.created_at, user: user}}
  end
end
```

### With Agents

```elixir
defmodule MyApp.Agents.DataProcessor do
  use Jido.Agent
  use Jido.TypeContract
  
  defcontract :state do
    required :status, :atom, in: [:idle, :processing, :complete]
    required :items_processed, :integer, min: 0
    optional :last_error, :string
  end
  
  @impl true
  @guard input: :state
  def on_before_run(agent) do
    # Validate state before running
    {:ok, agent}
  end
end
```

## Performance Considerations

1. **Compile-Time Optimization**: Contracts are compiled into efficient pattern matches
2. **Caching**: Validation results are cached for repeated validations
3. **Lazy Validation**: Only validates fields that are accessed
4. **Fast Path**: Skip validation in production with `:none` enforcement level

## Error Handling

All type violations result in detailed error structures:

```elixir
{:error, [
  %{
    field: :email,
    value: "invalid-email",
    error: "does not match format ~r/@/",
    path: [:user, :email]
  }
]}
```

## Telemetry Integration

The library emits telemetry events for monitoring:

- `[:jido, :type, :validation, :start]`
- `[:jido, :type, :validation, :stop]`
- `[:jido, :type, :violation]`
- `[:jido, :type, :cache, :hit]`
- `[:jido, :type, :cache, :miss]`

## Migration Path

1. Add `{:jido_type_enforcement, "~> 1.0"}` to deps
2. Add `use Jido.TypeContract` to modules
3. Define contracts for existing functions
4. Enable enforcement gradually with `Jido.TypeEnforcement.set_level(:log)`
5. Fix violations
6. Move to `:strict` enforcement