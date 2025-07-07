# Four Zone Architecture - The Complete Pattern

## Overview

The Four Zone Architecture represents perimeter's evolution from function-level validation to system-level architectural pattern. Each zone has distinct characteristics, responsibilities, and validation requirements.

## Zone Definitions

### Zone 1: External Perimeter
- **Purpose:** Validate all data entering the system from external sources
- **Characteristics:** Maximum validation, zero trust, comprehensive error handling
- **Performance:** Validation overhead acceptable for external boundaries

### Zone 2: Internal Perimeters  
- **Purpose:** Strategic boundaries between major subsystems
- **Characteristics:** Selective validation, domain-specific contracts, strategic coupling prevention
- **Performance:** Optimized validation, cached where possible

### Zone 3: Coupling Zones
- **Purpose:** Productive coupling between related components
- **Characteristics:** No validation overhead, shared data structures, direct function calls
- **Performance:** Maximum speed, zero validation cost

### Zone 4: Core Engine
- **Purpose:** Pure computational logic with maximum flexibility
- **Characteristics:** Full metaprogramming power, dynamic behavior, assertive programming
- **Performance:** Optimal Elixir performance

## Implementation Patterns

### Zone 1: External Perimeter Implementation

```elixir
defmodule MySystem.ExternalAPI do
  @moduledoc """
  Zone 1: All external input gets maximum validation.
  """
  
  use Perimeter.Zone1
  
  # Comprehensive contract for HTTP requests
  defcontract http_request :: %{
    required(:method) => :GET | :POST | :PUT | :DELETE,
    required(:path) => String.t(),
    required(:headers) => %{String.t() => String.t()},
    required(:body) => String.t() | nil,
    required(:query_params) => %{String.t() => String.t()},
    validate(:request_consistency),
    sanitize([:path, :body])
  }
  
  # Maximum validation with detailed error reporting
  @guard input: http_request(), 
         errors: :detailed,
         logging: :all_attempts,
         rate_limit: {100, :per_minute}
  def handle_request(request) do
    # Data is now 100% trusted for Zones 2-4
    InternalAPI.route_request(request)
  end
  
  # Custom validation functions
  defp request_consistency(request) do
    case {request.method, request.body} do
      {:GET, nil} -> :ok
      {:POST, body} when is_binary(body) -> :ok
      _ -> {:error, :invalid_method_body_combination}
    end
  end
end
```

### Zone 2: Internal Perimeter Implementation

```elixir
defmodule MySystem.AgentManager do
  @moduledoc """
  Zone 2: Strategic boundaries between major subsystems.
  """
  
  use Perimeter.Zone2
  
  # Domain-specific contracts
  defcontract agent_instruction :: %{
    required(:agent_id) => agent_id(),
    required(:action) => agent_action(),
    required(:params) => instruction_params(),
    optional(:context) => execution_context(),
    validate(:instruction_authorization)
  }
  
  defcontract agent_id :: String.t(), 
    pattern: ~r/^agent_[a-f0-9]{8}$/
    
  defcontract agent_action :: atom(),
    enum: [:execute, :query, :update, :optimize]
  
  # Optimized validation for internal boundaries
  @guard input: agent_instruction(),
         cache_validation: true,
         fast_path: [:agent_id],
         logging: :errors_only
  def execute_instruction(instruction) do
    # No more validation needed - move to coupling zone
    AgentCore.execute(instruction)
  end
  
  # Strategic boundary - prevent unauthorized access
  defp instruction_authorization(instruction) do
    if AgentRegistry.exists?(instruction.agent_id) do
      :ok
    else
      {:error, :agent_not_found}
    end
  end
end
```

### Zone 3: Coupling Zone Implementation

```elixir
defmodule MySystem.AgentCore do
  @moduledoc """
  Zone 3: Productive coupling - no validation overhead.
  """
  
  # NO use Perimeter - this is a coupling zone
  
  # Direct access to other coupling zone modules
  alias MySystem.{AgentRegistry, VariableExtractor, PipelineEngine}
  
  def execute(instruction) do
    # No validation - Zone 2 perimeter guarantees data integrity
    # Direct function calls, shared data structures
    
    agent = AgentRegistry.get!(instruction.agent_id)  # Assertive access
    variables = VariableExtractor.extract!(agent)      # Assertive access
    
    # Productive coupling - multiple modules work together
    instruction.action
    |> build_execution_plan(instruction.params, variables)
    |> PipelineEngine.execute()
    |> process_results(agent)
    |> update_agent_state()
  end
  
  # Helper functions with no validation
  defp build_execution_plan(action, params, variables) do
    %{
      action: action,
      params: params,
      variables: variables,
      steps: compile_steps(action, params),
      metadata: build_metadata()
    }
  end
  
  # Can use assertive programming - data is guaranteed valid
  defp compile_steps(:execute, %{pipeline: pipeline_spec}) do
    pipeline_spec.steps  # No safe access needed
  end
end
```

### Zone 4: Core Engine Implementation

```elixir
defmodule MySystem.PipelineEngine do
  @moduledoc """
  Zone 4: Core engine - maximum Elixir flexibility.
  """
  
  # Pure computational logic with full metaprogramming
  
  def execute(%{steps: steps, variables: variables} = plan) do
    # Can do anything - generate code, modify behavior, etc.
    # Zones 1-2 perimeters ensure we have valid data
    
    steps
    |> compile_to_functions(variables)
    |> create_execution_pipeline()
    |> run_with_telemetry(plan.metadata)
  end
  
  # Dynamic code generation
  defp compile_to_functions(steps, variables) do
    Enum.map(steps, fn step ->
      # Generate optimized functions at runtime
      compile_step_function(step, variables)
    end)
  end
  
  # Metaprogramming - create execution pipeline
  defp create_execution_pipeline(compiled_functions) do
    quote do
      fn input ->
        unquote(
          compiled_functions
          |> Enum.reduce(quote(do: input), fn func, acc ->
            quote do: unquote(func).(unquote(acc))
          end)
        )
      end
    end
    |> Code.eval_quoted()
    |> elem(0)
  end
  
  # Hot code swapping for optimization
  def optimize_pipeline(pipeline_id, new_variables) do
    # Can dynamically modify running pipelines
    # Zone validation ensures new_variables are valid
    Registry.update_value(PipelineRegistry, pipeline_id, fn current ->
      recompile_with_variables(current, new_variables)
    end)
  end
end
```

## Zone Transition Patterns

### Zone 1 → Zone 2 Transition

```elixir
defmodule TransitionPatterns.Zone1to2 do
  # Data flows from maximum validation to strategic validation
  
  def external_to_internal(external_data) do
    # Zone 1 validates everything
    case Perimeter.validate(external_data, :external_contract) do
      {:ok, validated} ->
        # Transform to internal representation
        internal_data = transform_to_internal(validated)
        
        # Pass to Zone 2
        InternalSubsystem.handle(internal_data)
        
      {:error, errors} ->
        # Handle validation failures at perimeter
        {:error, {:validation_failed, errors}}
    end
  end
end
```

### Zone 2 → Zone 3 Transition

```elixir
defmodule TransitionPatterns.Zone2to3 do
  # Data flows from strategic validation to coupling zone
  
  def strategic_to_coupling(strategic_data) do
    # Zone 2 provides strategic validation
    case Perimeter.validate(strategic_data, :strategic_contract) do
      {:ok, validated} ->
        # No more validation - enter coupling zone
        CouplingZone.process_directly(validated)
        
      {:error, reason} ->
        # Strategic boundary violation
        {:error, {:boundary_violation, reason}}
    end
  end
end
```

### Zone 3 → Zone 4 Transition

```elixir
defmodule TransitionPatterns.Zone3to4 do
  # Seamless flow from coupling to core engine
  
  def coupling_to_core(data) do
    # No validation needed - direct function call
    # Coupling zone guarantees data integrity
    CoreEngine.execute(data)
  end
end
```

## Performance Characteristics

### Zone 1: Maximum Overhead, Maximum Safety
```elixir
# Validation cost: High (10-100ms)
# Safety level: Maximum
# Use case: External API endpoints, file uploads, user input

@guard input: complex_external_contract(),
       validation_timeout: 100,
       detailed_errors: true,
       sanitization: true
```

### Zone 2: Optimized Overhead, Strategic Safety
```elixir
# Validation cost: Medium (1-10ms)  
# Safety level: Strategic
# Use case: Subsystem boundaries, service interfaces

@guard input: strategic_contract(),
       cache_validation: true,
       fast_path_fields: [:id, :type],
       error_mode: :simple
```

### Zone 3: Zero Overhead, Productive Coupling
```elixir
# Validation cost: Zero
# Safety level: Trust (from perimeter validation)
# Use case: Related modules working together

# No guards, direct function calls
def process(data), do: OtherModule.handle(data.field)
```

### Zone 4: Zero Overhead, Maximum Flexibility
```elixir
# Validation cost: Zero
# Safety level: Assertive programming
# Use case: Core algorithms, computational engines

# Pure functions with maximum optimization
def compute(data) do
  # Can use any Elixir feature without restriction
  data |> transform() |> optimize() |> execute()
end
```

## Architecture Benefits

### 1. **Gradual Validation Degradation**
- Maximum validation at system entry points
- Strategic validation at major boundaries  
- Zero validation in trusted zones
- Optimal performance profile

### 2. **Clear Responsibility Separation**
- Zone 1: Protects against external threats
- Zone 2: Manages internal complexity
- Zone 3: Enables productive coupling
- Zone 4: Maximizes computational efficiency

### 3. **Maintainable Complexity**
- Validation concentrated where it matters
- Clear boundaries between zones
- Predictable performance characteristics
- Easy to reason about data flow

### 4. **Elixir-Idiomatic Design**
- Embraces BEAM's strengths in each zone
- Allows metaprogramming where safe
- Supports productive coupling patterns
- Maintains fault tolerance principles

## Implementation Guidelines

### When to Use Each Zone

**Zone 1:** 
- HTTP API endpoints
- File system operations
- Database queries from external sources
- User input processing

**Zone 2:**
- Service boundaries in umbrella apps
- GenServer public APIs
- Plugin/extension points
- Cross-team interfaces

**Zone 3:**
- Related modules in same domain
- Helper function chains
- Data transformation pipelines
- Internal APIs

**Zone 4:**
- Mathematical computations
- String/data manipulation
- Algorithm implementations
- Performance-critical paths

This four-zone architecture provides a complete framework for building robust, performant Elixir applications with optimal validation placement.