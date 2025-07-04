# Perimeter Library Implementation Guide

## Overview

This guide maps the evolution from the Jido type system challenges to the innovative `perimeter` library, providing a comprehensive reference for implementing the "Defensive Perimeter / Offensive Interior" pattern in Elixir.

## Document Evolution Timeline

### Phase 1: Problem Discovery
- **0001.md**: Initial dialyzer type contract investigation revealing fundamental design flaws
- **0001_final_analysis.md**: Root cause identified - polymorphic struct anti-pattern
- **jido_architectural_analysis.md**: Comprehensive analysis of the architectural mismatch

### Phase 2: Innovation Design
- **type_perimeters_design.md**: Introduction of the three-zone model
- **type_enforcement_library_spec.md**: Detailed API specifications
- **type_relationships_formal_spec.md**: Formal type system relationships

### Phase 3: Synthesis with Elixir Best Practices
- **type_safe_metaprogramming_patterns.md**: Integration with metaprogramming
- **defensive_perimeter_implementation.md**: Practical implementation patterns
- **error_handling_type_safety.md**: Type-safe error perimeters
- **migration_strategy_guide.md**: Gradual adoption path

### Phase 4: Library Evolution (Post-Valim Talk)
- **PERIMETER_gem_0010.md**: Philosophical grounding based on Valim's principles
- **PERIMETER_gem_0011.md**: Migration guide and roadmap
- **PERIMETER_gem_0012.md**: Greenfield architecture patterns

## Core Innovation: The Three-Zone Model

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

### Zone Characteristics

1. **Defensive Perimeter**
   - Strict type validation at API perimeters
   - Contract enforcement via `@guard` macro
   - Structured error generation

2. **Transition Layer**
   - Type transformation and normalization
   - Safe atom conversion (avoiding dynamic atom creation)
   - Default value injection

3. **Offensive Interior**
   - Unrestricted metaprogramming
   - Assertive pattern matching
   - Trust in validated data

## Key Library Components

### 1. Contract Definition System
- **Module**: `Perimeter.Contract`
- **Key Features**:
  - `defcontract/2` macro for declarative contracts
  - `required/3` and `optional/3` field definitions
  - `compose/1` for contract composition
  - `validate/1` for custom validation functions

### 2. Guard Enforcement
- **Module**: `Perimeter.Guard`
- **Key Features**:
  - `@guard` attribute macro
  - Configurable enforcement levels (`:strict`, `:warn`, `:log`)
  - Input and output validation
  - Compile-time function wrapping

### 3. Runtime Validation
- **Module**: `Perimeter.Validator`
- **Key Features**:
  - `validate/3` for manual validation
  - `validate!/3` for exception-raising validation
  - Result caching for performance
  - Structured error responses

### 4. Error Handling
- **Module**: `Perimeter.Error`
- **Key Features**:
  - Structured violation tracking
  - Path-based error location
  - Integration with Phoenix/Absinthe
  - Telemetry emission

## Anti-Pattern Solutions

### 1. Non-Assertive Pattern Matching
- **Problem**: Defensive code with unclear failure modes
- **Solution**: Contracts guarantee structure, enabling assertive matching

### 2. Dynamic Atom Creation
- **Problem**: Memory leaks from uncontrolled atom creation
- **Solution**: Explicit atom mappings in contracts with `in:` constraints

### 3. Non-Assertive Map Access
- **Problem**: Using `map[:key]` for required fields
- **Solution**: Post-validation assertive access with `map.key`

### 4. Complex else Clauses
- **Problem**: Unclear error sources in with expressions
- **Solution**: Single validation point at function entry

## Implementation Patterns

### Pattern 1: Context Perimeters
```elixir
defmodule MyApp.Accounts do
  use Perimeter
  
  defcontract :create_user_params do
    required :email, :string, format: ~r/@/
    required :password, :string, min_length: 12
  end
  
  @guard input: :create_user_params
  def create_user(params) do
    # Assertive interior
  end
end
```

### Pattern 2: Phoenix Integration
```elixir
defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller
  use Perimeter
  
  plug :validate_params, contract: :create_params
  
  def create(conn, validated_params) do
    # Work with validated data
  end
end
```

### Pattern 3: GenServer Protection
```elixir
defmodule MyApp.Worker do
  use GenServer
  use Perimeter
  
  defcontract :job_params do
    required :type, :atom, in: [:sync, :async]
    required :payload, :map
  end
  
  @guard input: :job_params
  def handle_call({:process, params}, _from, state) do
    # Protected handler
  end
end
```

## Testing Strategy

### 1. Contract Testing
- Direct validation via `Perimeter.Validator`
- Property-based testing for contract coverage
- Contract composition verification

### 2. Guard Testing
- Happy path validation
- Error perimeter testing
- Enforcement level verification

### 3. Integration Testing
- Phoenix controller integration
- GenServer message validation
- Error propagation verification

## Performance Considerations

### 1. Compile-Time Optimization
- Contract compilation to pattern matches
- Static validation path generation
- Module attribute optimization

### 2. Runtime Optimization
- Validation result caching
- Lazy validation for large structures
- Fast-path for common patterns

### 3. Production Configuration
- `:log` level for monitoring
- Selective `:strict` enforcement
- Telemetry integration

## Migration Path

### For Existing Applications
1. Start with `:log` enforcement
2. Identify critical perimeters
3. Write shadow contracts
4. Fix upstream issues
5. Progress to `:warn` then `:strict`

### For New Applications
1. Design with contracts first
2. Use `:strict` in development/test
3. Guard all public APIs
4. Trust validated interiors

## Success Metrics

### Library Implementation
- All core modules compile without warnings
- 100% test coverage for public API
- Dialyzer compliance
- Documentation examples run correctly

### Integration Success
- Phoenix controller example works
- GenServer example works
- Error handling demonstrates proper structure
- Performance benchmarks show < 1% overhead

## References for Implementation

### Essential Reading Order
1. `type_perimeters_design.md` - Core innovation
2. `PERIMETER_gem_0010.md` - Philosophical foundation
3. `defensive_perimeter_implementation.md` - Practical patterns
4. `ELIXIR_1_20_0_DEV_ANTIPATTERNS.md` - Problems being solved

### Module-Specific References
- **Contract System**: `type_enforcement_library_spec.md`
- **Guard System**: `defensive_perimeter_implementation.md`
- **Error Handling**: `error_handling_type_safety.md`
- **Testing**: `PERIMETER_gem_0003.md`

## Final Implementation Notes

The `perimeter` library represents a synthesis of:
1. Solutions to real dialyzer issues in complex frameworks
2. Elixir community best practices and anti-pattern avoidance
3. José Valim's design principles for idiomatic Elixir
4. Practical patterns for large-scale applications

Success comes from focusing on the core innovation (the three-zone model) while maintaining simplicity and Elixir idioms throughout the implementation.