# Jido Type Boundaries Design: Defensive Perimeter with Offensive Interior

## Executive Summary

This document presents an innovative approach to type safety in Elixir metaprogramming, specifically designed for the Jido framework. We introduce a **"Defensive Boundary / Offensive Interior"** pattern that allows maximum metaprogramming flexibility while maintaining strict type contracts at system boundaries.

## Core Innovation: Type Enforcement Zones

### The Three-Zone Model

1. **Defensive Perimeter (Zone 1)**: Strict type validation at API boundaries
2. **Transition Layer (Zone 2)**: Type transformation and normalization
3. **Offensive Interior (Zone 3)**: Unrestricted metaprogramming with runtime guarantees

```
┌─────────────────────────────────────────────────┐
│            DEFENSIVE PERIMETER                  │
│  ┌───────────────────────────────────────────┐  │
│  │         TRANSITION LAYER                  │  │
│  │  ┌───────────────────────────────────┐   │  │
│  │  │    OFFENSIVE INTERIOR             │   │  │
│  │  │  (Metaprogramming Freedom)        │   │  │
│  │  └───────────────────────────────────┘   │  │
│  └───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
```

## Type Contract Enforcement Mechanisms

### 1. Compile-Time Contract Definition

```elixir
defmodule Jido.TypeContract do
  @moduledoc """
  Defines compile-time type contracts that are enforced at runtime boundaries.
  """
  
  defmacro defcontract(name, do: block) do
    quote do
      Module.register_attribute(__MODULE__, :type_contracts, accumulate: true)
      
      @type_contracts {unquote(name), unquote(Macro.escape(block))}
      
      def __contract__(unquote(name)) do
        unquote(block)
      end
    end
  end
end
```

### 2. Runtime Boundary Guards

```elixir
defmodule Jido.BoundaryGuard do
  @moduledoc """
  Enforces type contracts at runtime boundaries using pluggable validation strategies.
  """
  
  defmacro guard_boundary(function_name, contract_name) do
    quote do
      defoverridable [{unquote(function_name), 2}]
      
      def unquote(function_name)(params, context) do
        case Jido.BoundaryGuard.validate_input(__MODULE__, unquote(contract_name), params, context) do
          {:ok, validated_params, validated_context} ->
            result = super(validated_params, validated_context)
            Jido.BoundaryGuard.validate_output(__MODULE__, unquote(contract_name), result)
            
          {:error, violations} ->
            {:error, Jido.Error.validation_error("Contract violation", violations)}
        end
      end
    end
  end
end
```

### 3. Type Shape Definitions

```elixir
defmodule Jido.TypeShape do
  @moduledoc """
  Defines reusable type shapes that can be composed and validated.
  """
  
  defstruct [:name, :fields, :validators, :transformers]
  
  def shape(name, fields) do
    %__MODULE__{
      name: name,
      fields: normalize_fields(fields),
      validators: [],
      transformers: []
    }
  end
  
  def validate(%__MODULE__{} = shape, data) do
    # Efficient validation using compile-time optimized paths
  end
end
```

## Practical Implementation Strategy

### Phase 1: Boundary Identification

1. **Action Boundaries**
   - Entry: `Action.run/2`
   - Exit: Action result tuples
   - Contract: Input schema + Output schema

2. **Agent Boundaries**
   - Entry: `Agent.plan/3`, `Agent.run/1`
   - Exit: `Agent.result`
   - Contract: State schema + Instruction validation

3. **Instruction Boundaries**
   - Entry: `Instruction.normalize/3`
   - Exit: Normalized instruction structs
   - Contract: Action module validation + Params validation

### Phase 2: Contract Definition Language

```elixir
defmodule MyAction do
  use Jido.Action
  use Jido.TypeContract
  
  defcontract :input do
    required :user_id, :string, format: ~r/^user_\d+$/
    required :amount, :decimal, min: 0
    optional :metadata, :map do
      optional :source, :string
      optional :timestamp, :datetime
    end
  end
  
  defcontract :output do
    required :transaction_id, :string
    required :status, :atom, in: [:success, :pending, :failed]
    required :processed_at, :datetime
  end
  
  @impl true
  guard_boundary :run, :input
  def run(params, context) do
    # Interior zone - full metaprogramming freedom
    # Types are already validated at boundary
  end
end
```

### Phase 3: Progressive Type Enforcement

```elixir
defmodule Jido.TypeEnforcement do
  @enforcement_levels [:none, :log, :warn, :strict]
  
  def configure(module, level) when level in @enforcement_levels do
    # Configure per-module enforcement
  end
  
  defmacro enforce(level, do: block) do
    quote do
      old_level = Process.get(:type_enforcement_level, :warn)
      Process.put(:type_enforcement_level, unquote(level))
      try do
        unquote(block)
      after
        Process.put(:type_enforcement_level, old_level)
      end
    end
  end
end
```

## Type Relationship Tables

### Contract Inheritance Hierarchy

| Parent Type | Child Type | Inheritance Rule | Validation Strategy |
|-------------|------------|------------------|---------------------|
| `Jido.Agent.t()` | `MyAgent.t()` | Structural Extension | Parent fields + Child fields |
| `Action.result()` | `{:ok, map()}` | Tagged Union | Pattern match validation |
| `Instruction.t()` | Action module | Reference | Module behavior check |
| `Agent.state()` | User-defined map | Schema-based | NimbleOptions validation |

### Boundary Crossing Rules

| From Zone | To Zone | Required Validation | Transformation |
|-----------|---------|-------------------|----------------|
| External API | Defensive | Full contract validation | Input normalization |
| Defensive | Transition | Type shape verification | Structure alignment |
| Transition | Offensive | Minimal guards | None |
| Offensive | Transition | Result normalization | Output shaping |
| Transition | Defensive | Output contract validation | Error wrapping |

### Type Propagation Matrix

| Operation | Input Types | Output Types | Contract Enforcement |
|-----------|-------------|--------------|---------------------|
| `Action.run/2` | `params :: map(), context :: map()` | `{:ok, map()} \| {:error, Error.t()}` | Input schema + Output schema |
| `Agent.plan/3` | `agent :: t(), instruction, params` | `{:ok, t()}` | Instruction validation |
| `Exec.run/4` | `action :: module(), params, context, opts` | Action result type | Action contract |
| `Instruction.normalize/3` | Various formats | `{:ok, [Instruction.t()]}` | Structural validation |

## Custom Credo Checks

### 1. Boundary Violation Check

```elixir
defmodule Credo.Check.Warning.TypeBoundaryViolation do
  use Credo.Check
  
  def run(source_file, params) do
    # Detect direct field access across module boundaries
    # Flag any code that bypasses boundary guards
  end
end
```

### 2. Contract Completeness Check

```elixir
defmodule Credo.Check.Warning.IncompleteTypeContract do
  use Credo.Check
  
  def run(source_file, params) do
    # Ensure all public functions have contracts
    # Verify contract coverage
  end
end
```

## Programmatic Type Enforcement

### Runtime Contract Validation

```elixir
defmodule Jido.Runtime.TypeValidator do
  @moduledoc """
  Provides runtime type validation with performance optimization.
  """
  
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def validate(module, function, args) do
    GenServer.call(__MODULE__, {:validate, module, function, args})
  end
  
  @impl true
  def init(opts) do
    # Build optimized validation paths at startup
    {:ok, build_validation_cache(opts)}
  end
end
```

### Development Mode Type Checking

```elixir
defmodule Jido.Dev.TypeChecker do
  @moduledoc """
  Enhanced type checking for development mode with detailed reporting.
  """
  
  defmacro __using__(_opts) do
    if Mix.env() == :dev do
      quote do
        @before_compile Jido.Dev.TypeChecker
      end
    end
  end
  
  defmacro __before_compile__(_env) do
    quote do
      def __type_check__ do
        # Perform comprehensive type analysis
        # Generate detailed type reports
      end
    end
  end
end
```

## Integration with Existing Patterns

### 1. With NimbleOptions

```elixir
defmodule Jido.TypeContract.NimbleAdapter do
  def to_nimble_schema(contract) do
    # Convert TypeContract to NimbleOptions schema
  end
  
  def from_nimble_schema(schema) do
    # Convert NimbleOptions schema to TypeContract
  end
end
```

### 2. With Dialyzer

```elixir
defmodule Jido.TypeContract.DialyzerHints do
  @moduledoc """
  Generates Dialyzer-compatible type specifications from contracts.
  """
  
  defmacro generate_specs(contract_name) do
    quote do
      @spec unquote(contract_name)(map()) :: {:ok, map()} | {:error, [violation()]}
    end
  end
end
```

## Benefits of This Approach

1. **Practical**: Works with existing Elixir tooling
2. **Flexible**: Allows full metaprogramming within boundaries
3. **Safe**: Enforces contracts at critical points
4. **Performant**: Validation only at boundaries, not throughout
5. **Gradual**: Can be adopted incrementally
6. **Debuggable**: Clear violation reports with context

## Next Steps

1. Implement core `Jido.TypeContract` module
2. Create boundary guard macros
3. Develop Credo checks for boundary violations
4. Build development-mode type checker
5. Create migration guide for existing code