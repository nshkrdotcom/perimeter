# Type-Safe Metaprogramming Patterns for Elixir

## Overview

This guide synthesizes the innovative "Defensive Boundary / Offensive Interior" pattern with Elixir's idioms to create type-safe metaprogramming practices that avoid common antipatterns while preserving the language's dynamic power.

## Core Principle: Assertive Boundaries, Dynamic Interiors

The fundamental insight is that type safety in Elixir doesn't require abandoning metaprogramming. Instead, we establish **assertive type boundaries** around **dynamic interiors**, creating zones where different rules apply:

1. **Boundary Zone**: Strict validation, pattern matching, and type contracts
2. **Interior Zone**: Full metaprogramming freedom with runtime guarantees

This approach directly addresses the antipatterns of non-assertive programming while enabling powerful dynamic features.

## Pattern 1: Contract-Based Module Generation

### Antipattern Avoided: Non-Assertive Pattern Matching

Instead of defensive programming that accepts any input, we use contracts to enforce structure at compile-time:

```elixir
defmodule Jido.DefineAction do
  use Jido.TypeContract
  
  defcontract :action_definition do
    required :name, :atom
    required :schema, :keyword_list
    optional :output_schema, :keyword_list
    optional :description, :string
  end
  
  defmacro define_action(definition) do
    # Validate at compile time
    case validate_contract(:action_definition, definition) do
      {:ok, validated} ->
        generate_action_module(validated)
      {:error, violations} ->
        raise CompileError, description: format_violations(violations)
    end
  end
  
  defp generate_action_module(definition) do
    quote do
      defmodule unquote(definition.name) do
        use Jido.Action
        
        # Metaprogramming interior - validated data allows freedom
        unquote(generate_schema(definition.schema))
        unquote(generate_callbacks(definition))
      end
    end
  end
end
```

### Usage

```elixir
# Compile-time validation ensures correctness
DefineAction.define_action(
  name: MyApp.Actions.CreateUser,
  schema: [
    name: [type: :string, required: true],
    email: [type: :string, format: ~r/@/]
  ],
  output_schema: [
    id: [type: :string],
    created_at: [type: :datetime]
  ]
)
```

## Pattern 2: Assertive Dynamic Dispatch

### Antipattern Avoided: Dynamic Atom Creation

Instead of converting arbitrary strings to atoms, we use a registry pattern with explicit contracts:

```elixir
defmodule Jido.ActionRegistry do
  use GenServer
  use Jido.TypeContract
  
  defcontract :registration do
    required :name, :string, format: ~r/^[a-z_]+$/
    required :module, :atom
    required :category, :atom, in: [:data, :workflow, :integration]
  end
  
  def register_action(attrs) do
    with {:ok, validated} <- validate_contract(:registration, attrs),
         :ok <- validate_module_exists(validated.module),
         :ok <- validate_implements_behavior(validated.module, Jido.Action) do
      GenServer.call(__MODULE__, {:register, validated})
    end
  end
  
  def dispatch(name, params, context) when is_binary(name) do
    case lookup_action(name) do
      {:ok, module} ->
        # Boundary crossed - now in validated interior
        Jido.Exec.run(module, params, context)
      :error ->
        {:error, Jido.Error.not_found("Action not registered", %{name: name})}
    end
  end
  
  defp lookup_action(name) do
    # No dynamic atom creation - only pre-registered atoms
    GenServer.call(__MODULE__, {:lookup, name})
  end
end
```

## Pattern 3: Type-Safe Dynamic Configuration

### Antipattern Avoided: Non-Assertive Map Access

Instead of defensive map access, we use structured configuration with compile-time validation:

```elixir
defmodule Jido.Config do
  use Jido.TypeContract
  
  defcontract :action_config do
    required :timeout, :integer, min: 0, max: 300_000
    required :retries, :integer, min: 0, max: 10
    optional :telemetry, :atom, in: [:full, :minimal, :none]
    
    optional :hooks, :map do
      optional :before_run, {:list, :atom}
      optional :after_run, {:list, :atom}
    end
  end
  
  defmacro configure(module, config) do
    case validate_contract(:action_config, config) do
      {:ok, validated} ->
        quote do
          @action_config unquote(Macro.escape(validated))
          
          # Assertive access - we know these fields exist
          def timeout, do: @action_config.timeout
          def retries, do: @action_config.retries
          
          # Optional access for optional fields
          def telemetry, do: @action_config[:telemetry] || :minimal
          def hooks, do: @action_config[:hooks] || %{}
        end
      {:error, violations} ->
        raise CompileError, description: format_violations(violations)
    end
  end
end

# Usage
defmodule MyAction do
  use Jido.Action
  use Jido.Config
  
  configure MyAction,
    timeout: 5_000,
    retries: 3,
    hooks: %{
      before_run: [:validate_permissions, :log_attempt]
    }
end
```

## Pattern 4: Boundary-Enforced Metaprogramming

### Antipattern Avoided: Complex else Clauses in with

Instead of complex error handling, we normalize at boundaries:

```elixir
defmodule Jido.Workflow do
  use Jido.TypeContract
  
  defcontract :step do
    required :action, :atom
    required :input_transform, :function
    required :error_handler, :atom, in: [:retry, :skip, :halt]
  end
  
  defmacro defworkflow(name, steps) do
    validated_steps = Enum.map(steps, fn step ->
      case validate_contract(:step, step) do
        {:ok, valid} -> valid
        {:error, violations} ->
          raise CompileError, description: 
            "Invalid workflow step: #{format_violations(violations)}"
      end
    end)
    
    quote do
      def unquote(name)(initial_params, context) do
        # Interior: validated steps allow clean with expression
        unquote(generate_workflow_with(validated_steps))
      end
    end
  end
  
  defp generate_workflow_with(steps) do
    # Generate clean with expression without complex else
    step_clauses = Enum.map(steps, fn step ->
      quote do
        {unquote(step.action), result} <- 
          execute_step(unquote(step), previous_result)
      end
    end)
    
    quote do
      with unquote_splicing(step_clauses) do
        {:ok, result}
      end
    end
  end
  
  defp execute_step(step, input) do
    # Boundary enforcement before action execution
    transformed = step.input_transform.(input)
    
    case Jido.Exec.run(step.action, transformed, %{}) do
      {:ok, result} -> {step.action, {:ok, result}}
      {:error, error} -> handle_step_error(step, error)
    end
  end
end
```

## Pattern 5: Type-Safe Code Generation

### Combining Multiple Patterns

This example shows how to combine assertive boundaries with dynamic code generation:

```elixir
defmodule Jido.GenerateStateMachine do
  use Jido.TypeContract
  
  defcontract :state_definition do
    required :name, :atom
    required :events, {:list, :event}
  end
  
  defcontract :event do
    required :name, :atom
    required :from, {:list, :atom}
    required :to, :atom
    optional :guard, :function
  end
  
  defmacro generate(definition) do
    with {:ok, validated} <- validate_contract(:state_definition, definition),
         :ok <- validate_state_graph(validated) do
      generate_state_machine(validated)
    else
      {:error, reason} ->
        raise CompileError, description: format_error(reason)
    end
  end
  
  defp generate_state_machine(%{name: name, events: events}) do
    # Assertive pattern matching on validated structure
    event_functions = Enum.map(events, &generate_event_function/1)
    
    quote do
      defmodule unquote(name) do
        use GenServer
        
        # Type contracts for runtime boundaries
        use Jido.TypeContract
        
        defcontract :state do
          required :current, :atom
          required :data, :map
          required :history, {:list, :atom}
        end
        
        # Generated functions with boundary guards
        unquote_splicing(event_functions)
        
        # Assertive state access
        def current_state(%{current: current}), do: current
        def state_data(%{data: data}), do: data
      end
    end
  end
  
  defp generate_event_function(%{name: event, from: from_states, to: to_state} = event_def) do
    quote do
      def unquote(event)(state) do
        # Pattern match ensures we're in a valid from state
        %{current: current} = state
        
        if current in unquote(from_states) do
          # Apply guard if present
          if unquote(apply_guard(event_def)) do
            {:ok, %{state | current: unquote(to_state), 
                           history: [current | state.history]}}
          else
            {:error, :guard_failed}
          end
        else
          {:error, {:invalid_transition, current, unquote(event)}}
        end
      end
    end
  end
end
```

## Best Practices Summary

### 1. Validate at Compile Time When Possible

```elixir
# Good: Compile-time validation
defmacro define_handler(name, opts) do
  validated_opts = validate_at_compile_time!(opts)
  # ... generate code with validated opts
end

# Avoid: Runtime validation in macros
defmacro define_handler(name, opts) do
  quote do
    opts = validate_opts(unquote(opts))  # Too late!
  end
end
```

### 2. Use Pattern Matching for Structure Assertion

```elixir
# Good: Assertive pattern matching
def process(%User{id: id, name: name} = user) when is_binary(name) do
  # We know the structure is correct
end

# Avoid: Defensive checking
def process(user) do
  if is_map(user) && Map.has_key?(user, :id) do
    # Defensive and unclear
  end
end
```

### 3. Separate Boundary Validation from Interior Logic

```elixir
defmodule MyAction do
  # Boundary: strict validation
  @guard input: :user_input
  def run(params, context) do
    # Interior: work with validated data
    transform_and_process(params)
  end
  
  # Pure interior logic without validation concerns
  defp transform_and_process(validated_params) do
    # Free to use metaprogramming, dynamic dispatch, etc.
  end
end
```

### 4. Make Contracts Explicit and Reusable

```elixir
defmodule SharedContracts do
  use Jido.TypeContract
  
  defcontract :pagination do
    optional :page, :integer, min: 1, default: 1
    optional :limit, :integer, min: 1, max: 100, default: 20
  end
  
  defcontract :user_identity do
    required :user_id, :string, format: ~r/^user_\d+$/
    optional :session_id, :string
  end
end
```

### 5. Provide Clear Error Messages at Boundaries

```elixir
def create_action(params) do
  case validate_contract(:action_params, params) do
    {:ok, validated} ->
      do_create(validated)
    {:error, violations} ->
      {:error, %Jido.Error{
        type: :validation_error,
        message: "Invalid action parameters",
        details: %{
          violations: format_violations(violations),
          hint: "Check the required fields and their types"
        }
      }}
  end
end
```

## Conclusion

By combining the "Defensive Boundary / Offensive Interior" pattern with Elixir's existing idioms, we can write code that is both type-safe and dynamically powerful. The key is to:

1. **Be assertive at boundaries** - Use pattern matching, guards, and contracts
2. **Validate early** - Catch errors at compile-time when possible
3. **Trust the interior** - Once validated, use Elixir's full power
4. **Make contracts explicit** - Clear, reusable type definitions
5. **Fail fast and clearly** - Provide actionable error messages

This approach gives us the best of both worlds: the safety of typed systems at boundaries and the flexibility of dynamic metaprogramming in our implementation.