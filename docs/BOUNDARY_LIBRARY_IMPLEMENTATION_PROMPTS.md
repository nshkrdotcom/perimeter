# Boundary Library Implementation Prompts

## Overview
This document contains a series of incremental prompts for implementing the `boundary` library. Each prompt is self-contained, includes all necessary context, and has clear success metrics.

---

## Prompt 1: Core Contract DSL Foundation

### Context
You are implementing the `boundary` library for Elixir, which provides runtime type validation at system boundaries. Read these references:
- **Primary**: `BOUNDARY_LIBRARY_IMPLEMENTATION_GUIDE.md` sections "Core Innovation" and "Key Library Components"
- **Secondary**: `type_enforcement_library_spec.md` section on `Jido.TypeContract`

### Task
Implement the basic contract definition DSL in `lib/boundary/contract.ex`:

1. Create the `defcontract/2` macro that:
   - Accepts a name (atom) and a do block
   - Stores contract definitions in module attributes
   - Generates a `__contract__/1` function

2. Implement `required/3` and `optional/3` macros that:
   - Accept field name, type, and options
   - Build field specifications

3. Create basic type atoms:
   - `:string`, `:integer`, `:boolean`, `:atom`, `:map`

### Success Metrics
```elixir
# This should compile without warnings:
defmodule TestContract do
  use Boundary.Contract
  
  defcontract :user do
    required :name, :string
    optional :age, :integer
  end
end

# This should return contract data:
TestContract.__contract__(:user)
```

### Manual Verification
1. Run `mix compile --warnings-as-errors`
2. Check that `__contract__/1` returns a data structure with field definitions
3. Verify no compiler warnings about undefined macros

---

## Prompt 2: Contract Validation Engine

### Context
Building on Prompt 1's contract DSL. Read these references:
- **Primary**: `defensive_boundary_implementation.md` section "Contract Validation Engine"
- **Secondary**: `type_contract_best_practices.md` section "Fail Fast with Clear Messages"

### Task
Implement the validation engine in `lib/boundary/validator.ex`:

1. Create `validate/3` function that:
   - Takes module, contract name, and data map
   - Returns `{:ok, data}` or `{:error, %Boundary.Error{}}`
   - Validates required fields exist
   - Validates optional fields if present
   - Checks basic type constraints

2. Implement type validators for:
   - `:string` - `is_binary/1`
   - `:integer` - `is_integer/1`
   - `:boolean` - `is_boolean/1`
   - `:atom` - `is_atom/1`
   - `:map` - `is_map/1`

3. Create `Boundary.Error` struct with:
   - `violations` list
   - Each violation has: `field`, `error`, `value`, `path`

### Success Metrics
```elixir
# Valid data passes:
{:ok, _} = Boundary.Validator.validate(TestContract, :user, %{name: "John"})

# Invalid data fails with structured error:
{:error, %Boundary.Error{violations: [
  %{field: :name, error: "is required"}
]}} = Boundary.Validator.validate(TestContract, :user, %{})

# Type mismatch caught:
{:error, %Boundary.Error{violations: [
  %{field: :name, error: "expected string, got integer"}
]}} = Boundary.Validator.validate(TestContract, :user, %{name: 123})
```

### Manual Verification
1. Create test module with various contracts
2. Test validation with valid/invalid data
3. Inspect error structures for clarity
4. Run dialyzer to check type specifications

---

## Prompt 3: Field Constraints Implementation

### Context
Extending the validation engine with constraints. Read:
- **Primary**: `type_enforcement_library_spec.md` section on field options
- **Secondary**: `ELIXIR_1_20_0_DEV_ANTIPATTERNS.md` section "Dynamic Atom Creation"

### Task
Add constraint validation to the validator:

1. String constraints:
   - `min_length:` and `max_length:`
   - `format:` (regex pattern)

2. Number constraints:
   - `min:` and `max:`

3. Atom constraints:
   - `in:` (list of allowed atoms)
   - Prevent dynamic atom creation

4. List constraints:
   - `min_items:` and `max_items:`

### Success Metrics
```elixir
defmodule ConstraintTest do
  use Boundary.Contract
  
  defcontract :validated do
    required :email, :string, format: ~r/@/
    required :age, :integer, min: 18, max: 100
    required :status, :atom, in: [:active, :inactive]
  end
end

# Constraints work:
{:ok, _} = validate(ConstraintTest, :validated, %{
  email: "test@example.com",
  age: 25,
  status: :active
})

# Format constraint fails:
{:error, %{violations: [%{field: :email, error: "invalid format"}]}} = 
  validate(ConstraintTest, :validated, %{email: "notanemail", age: 25, status: :active})
```

### Manual Verification
1. Test each constraint type individually
2. Verify constraint combinations work
3. Check that `in:` constraint prevents atom creation attacks
4. Ensure helpful error messages

---

## Prompt 4: Guard Macro Foundation

### Context
Implementing the `@guard` attribute macro. Read:
- **Primary**: `defensive_boundary_implementation.md` section "Boundary Guard Module"
- **Secondary**: `PERIMETER_gem_0002.md` section on guard mechanics

### Task
Create `lib/boundary/guard.ex` with:

1. Basic `@guard` attribute that:
   - Stores guard configuration
   - Triggers function wrapping at compile time

2. Function wrapping that:
   - Intercepts the original function
   - Validates first argument against input contract
   - Calls original function if valid
   - Returns `{:error, %Boundary.Error{}}` if invalid

3. Support `:input` option only (not `:output` yet)

### Success Metrics
```elixir
defmodule GuardedModule do
  use Boundary
  
  defcontract :params do
    required :id, :integer
  end
  
  @guard input: :params
  def process(params) do
    {:ok, params.id * 2}
  end
end

# Valid input works:
{:ok, 10} = GuardedModule.process(%{id: 5})

# Invalid input caught:
{:error, %Boundary.Error{}} = GuardedModule.process(%{id: "not-an-int"})
```

### Manual Verification
1. Use `IO.inspect` to verify guard intercepted call
2. Check that original function body only runs with valid data
3. Test with multiple function clauses
4. Verify compilation performance is reasonable

---

## Prompt 5: Enforcement Levels

### Context
Adding configurable enforcement. Read:
- **Primary**: `migration_strategy_guide.md` section "Progressive Type Enforcement"
- **Secondary**: `PERIMETER_gem_0011.md` section on enforcement levels

### Task
Implement enforcement level system:

1. Add configuration:
   ```elixir
   config :boundary, enforcement_level: :strict
   ```

2. Support three levels:
   - `:strict` - Return error, don't call function
   - `:warn` - Log warning, call function anyway
   - `:log` - Log info, call function anyway

3. Add `:enforcement` option to `@guard`:
   ```elixir
   @guard input: :params, enforcement: :log
   ```

4. Create `Boundary.Config` module for runtime configuration

### Success Metrics
```elixir
# With :log enforcement
Application.put_env(:boundary, :enforcement_level, :log)

# Invalid data logs but continues:
capture_log(fn ->
  {:ok, nil} = GuardedModule.process(%{})  # Function runs despite invalid data
end) =~ "Boundary contract violation"

# With :strict enforcement
Application.put_env(:boundary, :enforcement_level, :strict)

# Invalid data returns error:
{:error, %Boundary.Error{}} = GuardedModule.process(%{})
```

### Manual Verification
1. Test each enforcement level
2. Verify log output format is helpful
3. Check that per-guard enforcement overrides global
4. Test configuration changes at runtime

---

## Prompt 6: Nested Contracts

### Context
Supporting nested data structures. Read:
- **Primary**: `type_contract_best_practices.md` section "Use Composition"
- **Secondary**: Nested contract examples in `BOUNDARY_LIBRARY_IMPLEMENTATION_GUIDE.md`

### Task
Add support for nested contracts:

1. Map nesting:
   ```elixir
   required :address, :map do
     required :street, :string
     optional :zip, :string
   end
   ```

2. List of maps:
   ```elixir
   required :items, {:list, :map} do
     required :id, :integer
     required :name, :string
   end
   ```

3. Update validator to handle nested validation
4. Ensure error paths are correct for nested fields

### Success Metrics
```elixir
defcontract :order do
  required :id, :integer
  required :customer, :map do
    required :name, :string
    required :email, :string
  end
  required :items, {:list, :map} do
    required :sku, :string
    required :quantity, :integer
  end
end

# Nested validation works:
{:ok, _} = validate(TestMod, :order, %{
  id: 1,
  customer: %{name: "John", email: "j@example.com"},
  items: [%{sku: "ABC", quantity: 2}]
})

# Nested errors have correct paths:
{:error, %{violations: [
  %{field: :email, path: [:customer, :email], error: "is required"}
]}} = validate(TestMod, :order, %{
  id: 1,
  customer: %{name: "John"},
  items: []
})
```

### Manual Verification
1. Test deeply nested structures (3+ levels)
2. Verify path construction is correct
3. Test empty lists and maps
4. Check performance with large nested structures

---

## Prompt 7: Custom Validators

### Context
Adding custom validation functions. Read:
- **Primary**: `type_contract_best_practices.md` section "Separate Validation from Business Logic"
- **Secondary**: `defensive_boundary_implementation.md` Custom validator examples 

### Task
Implement custom validation support:

1. Add `validate/1` macro to contract DSL:
   ```elixir
   defcontract :user do
     required :password, :string
     required :password_confirmation, :string
     validate :passwords_match
   end
   ```

2. Custom validators should:
   - Receive the validated data map
   - Return `:ok` or `{:error, violation_map}`
   - Run after field validation
   - Have access to all fields

3. Support multiple validators per contract

### Success Metrics
```elixir
defmodule CustomTest do
  use Boundary.Contract
  
  defcontract :registration do
    required :password, :string, min_length: 8
    required :password_confirmation, :string
    validate :passwords_match
  end
  
  defp passwords_match(%{password: p, password_confirmation: pc}) do
    if p == pc do
      :ok
    else
      {:error, %{field: :password_confirmation, error: "does not match password"}}
    end
  end
end

# Custom validation works:
{:error, %{violations: [
  %{field: :password_confirmation, error: "does not match password"}
]}} = validate(CustomTest, :registration, %{
  password: "secret123",
  password_confirmation: "different"
})
```

### Manual Verification
1. Test validator execution order
2. Verify validators can access all fields
3. Test multiple validators on same contract
4. Ensure validators can't modify data

---

## Prompt 8: Contract Composition

### Context
Implementing contract reuse. Read:
- **Primary**: `type_contract_best_practices.md` section "Compose, Don't Repeat"
- **Secondary**: `BOUNDARY_LIBRARY_IMPLEMENTATION_GUIDE.md` Examples of shared contracts

### Task
Add `compose/1` macro for contract composition:

1. Allow composing single or multiple contracts:
   ```elixir
   defcontract :timestamped do
     compose :timestamps
     required :title, :string
   end
   ```

2. Handle field conflicts (last wins)
3. Compose validators as well
4. Support cross-module composition

### Success Metrics
```elixir
defmodule SharedContracts do
  use Boundary.Contract
  
  defcontract :timestamps do
    required :inserted_at, :datetime
    required :updated_at, :datetime
  end
end

defmodule UserContracts do
  use Boundary.Contract
  import SharedContracts
  
  defcontract :user do
    required :email, :string
    compose :timestamps
  end
end

# Composition works:
{:ok, _} = validate(UserContracts, :user, %{
  email: "test@example.com",
  inserted_at: DateTime.utc_now(),
  updated_at: DateTime.utc_now()
})

# Missing composed field caught:
{:error, %{violations: [%{field: :inserted_at}]}} = 
  validate(UserContracts, :user, %{email: "test@example.com"})
```

### Manual Verification
1. Test single and multiple composition
2. Verify field override behavior
3. Test circular composition detection
4. Check cross-module imports work

---

## Prompt 9: Phoenix Integration

### Context
Creating Phoenix-specific helpers. Read:
- **Primary**: `greenfield_architecture.md` section "Build the Web Boundary"
- **Secondary**: `BOUNDARY_LIBRARY_IMPLEMENTATION_GUIDE.md` Phoenix controller examples

### Task
Create `lib/boundary/phoenix.ex` with:

1. Plug for parameter validation:
   ```elixir
   plug Boundary.Phoenix.ValidateParams, contract: :create_user
   ```

2. FallbackController helper for errors
3. Helper for validated params access
4. JSON error formatting

### Success Metrics
```elixir
defmodule TestController do
  use Phoenix.Controller
  use Boundary
  
  plug Boundary.Phoenix.ValidateParams, 
    contract: :create_params when action == :create
  
  defcontract :create_params do
    required :user, :map do
      required :email, :string
    end
  end
  
  def create(conn, _params) do
    # Validated params available
    validated = conn.assigns.boundary_params
    json(conn, %{email: validated.user.email})
  end
end

# Invalid params return 422:
conn = conn(:post, "/users", %{user: %{}})
conn = TestController.call(conn, :create)
assert conn.status == 422
assert conn.resp_body =~ "email is required"
```

### Manual Verification
1. Test with real Phoenix app
2. Verify plug pipeline integration
3. Test error response format
4. Check performance impact

---

## Prompt 10: Documentation and Examples

### Context
Creating comprehensive documentation. Read:
- **Primary**: All PERIMETER_gem_* files for structure
- **Secondary**: `BOUNDARY_LIBRARY_IMPLEMENTATION_GUIDE.md`

### Task
Create documentation:

1. Complete README.md with:
   - Philosophy section
   - Quick start example
   - Installation instructions

2. Add @moduledoc to all modules
3. Add @doc to all public functions
4. Create `examples/` directory with:
   - Phoenix app example
   - GenServer example
   - Plain module example

### Success Metrics
```bash
# Documentation builds without warnings:
mix docs

# Examples run without errors:
cd examples/phoenix_app && mix test
cd examples/genserver && mix test

# Doctests pass:
mix test --only doctest
```

### Manual Verification
1. Review generated docs for clarity
2. Test all code examples work
3. Check cross-references are correct
4. Verify examples demonstrate key patterns

---

## Prompt 11: Performance Optimization

### Context
Optimizing for production use. Read:
- **Primary**: `defensive_boundary_implementation.md` section "Performance Optimization"
- **Secondary**: `BOUNDARY_CACHING_STRATEGIES.md` Caching strategies

### Task
Add performance optimizations:

1. Compile contracts at compile-time into optimized validators
2. Add simple validation result caching
3. Implement fast paths for common patterns
4. Add benchmarks in `bench/` directory

### Success Metrics
```elixir
# Benchmark shows < 1% overhead:
Benchee.run(%{
  "without_boundary" => fn -> 
    MyModule.unguarded_function(%{id: 1})
  end,
  "with_boundary" => fn ->
    MyModule.guarded_function(%{id: 1})
  end
})

# Results show minimal overhead:
# with_boundary is at most 1.01x slower than without_boundary
```

### Manual Verification
1. Run benchmarks with various data sizes
2. Profile memory usage
3. Test cache hit rates
4. Verify no memory leaks

---

## Prompt 12: Final Integration Tests

### Context
Ensuring everything works together. Read:
- **Primary**: Testing sections from all guides
- **Secondary**: `BOUNDARY_LIBRARY_IMPLEMENTATION_GUIDE.md` success metrics

### Task
Create comprehensive integration tests:

1. Full Phoenix application test
2. GenServer with guards test  
3. Multi-module contract sharing test
4. Error propagation test
5. Configuration change test

### Success Metrics
```bash
# All tests pass:
mix test

# Dialyzer passes:
mix dialyzer

# Credo passes:
mix credo --strict

# Coverage is 100% for public API:
mix test --cover
```

### Manual Verification
1. Review test coverage report
2. Manually test with a real app
3. Check all examples still work
4. Verify no regression in previous functionality

---

## Implementation Order and Dependencies

1. **Prompts 1-2**: Core foundation (must be done first)
2. **Prompts 3-4**: Extended functionality (requires 1-2)
3. **Prompts 5-6**: Advanced features (requires 3-4)
4. **Prompts 7-8**: Composition features (requires 1-6)
5. **Prompt 9**: Framework integration (requires 1-8)
6. **Prompts 10-12**: Polish and optimization (requires all previous)

## Notes for Manual Review

After each prompt:
1. Run `mix compile --warnings-as-errors`
2. Run `mix format --check-formatted`
3. Run `mix dialyzer` (after prompt 4)
4. Commit working code before next prompt
5. Tag successful milestone implementations

The library should be shippable after Prompt 9, with 10-12 adding polish and performance.
