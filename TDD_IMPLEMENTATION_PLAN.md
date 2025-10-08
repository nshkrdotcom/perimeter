# Perimeter MVP: TDD Implementation Plan

## MVP Scope Definition

### What We're Building (v0.1.0)

**Core Value Proposition**: Enable developers to define and enforce data contracts at function perimeters with minimal friction.

**Three Modules Only**:
1. `Perimeter.Contract` - Define contracts with DSL
2. `Perimeter.Validator` - Runtime validation engine
3. `Perimeter.Guard` - Function-level enforcement via macros

**Explicitly OUT of MVP**:
- ❌ Output validation (input only)
- ❌ Enforcement levels (:log/:warn - strict only)
- ❌ Caching/performance optimization
- ❌ Perimeter.Interface (Strategy pattern support)
- ❌ Custom Credo checks
- ❌ Ecto/Phoenix integration helpers
- ❌ Telemetry (add in v0.2)

### Success Criteria

```elixir
# This should work by end of MVP:
defmodule MyApp.Accounts do
  use Perimeter

  defcontract :create_user do
    required :email, :string, format: ~r/@/
    required :password, :string, min_length: 12
    optional :name, :string, max_length: 100
  end

  @guard input: :create_user
  def create_user(params) do
    # params guaranteed valid here
    {:ok, %{email: params.email}}
  end
end

# Valid call
MyApp.Accounts.create_user(%{
  email: "test@example.com",
  password: "secret123456"
})
# => {:ok, %{email: "test@example.com"}}

# Invalid call
MyApp.Accounts.create_user(%{email: "invalid"})
# => raises Perimeter.ValidationError with clear message
```

---

## TDD Strategy

### Test-First Development Cycle

For each feature:
1. **Write failing test** - Document expected behavior
2. **Run test** - Confirm it fails for the right reason
3. **Implement minimum code** - Make test pass
4. **Refactor** - Clean up while keeping tests green
5. **Document** - Add @doc with examples from tests

### Test Organization

```
test/
  perimeter/
    contract_test.exs          # Contract DSL tests
    validator_test.exs         # Validation logic tests
    guard_test.exs             # Guard macro tests
    integration_test.exs       # End-to-end scenarios
  support/
    test_schemas.ex            # Reusable test contracts
  perimeter_test.exs           # Main module tests
```

---

## Phase 1: Contract Definition (Week 1)

### Feature 1.1: Basic Contract Structure

**Test First**:
```elixir
# test/perimeter/contract_test.exs
defmodule Perimeter.ContractTest do
  use ExUnit.Case

  test "defines a contract with required fields" do
    defmodule TestContract do
      use Perimeter.Contract

      defcontract :user do
        required :name, :string
        required :age, :integer
      end
    end

    contract = TestContract.__contract__(:user)
    assert contract.name == :user
    assert length(contract.fields) == 2
  end
end
```

**Implementation Order**:
1. Create `lib/perimeter/contract.ex`
2. Implement `use Perimeter.Contract` macro
3. Implement `defcontract/2` macro
4. Implement `required/3` macro
5. Build internal contract representation (struct)

### Feature 1.2: Optional Fields

**Test First**:
```elixir
test "supports optional fields" do
  defmodule TestContract do
    use Perimeter.Contract

    defcontract :user do
      required :email, :string
      optional :bio, :string
    end
  end

  contract = TestContract.__contract__(:user)
  required_field = Enum.find(contract.fields, & &1.name == :email)
  optional_field = Enum.find(contract.fields, & &1.name == :bio)

  assert required_field.required == true
  assert optional_field.required == false
end
```

**Implementation**: Add `optional/3` macro

### Feature 1.3: Field Constraints

**Test First**:
```elixir
test "supports field constraints" do
  defmodule TestContract do
    use Perimeter.Contract

    defcontract :user do
      required :email, :string, format: ~r/@/
      required :age, :integer, min: 0, max: 150
    end
  end

  contract = TestContract.__contract__(:user)
  email_field = Enum.find(contract.fields, & &1.name == :email)

  assert email_field.constraints[:format] == ~r/@/
end
```

**Implementation**: Store constraints in field definition

### Feature 1.4: Nested Contracts

**Test First**:
```elixir
test "supports nested field definitions" do
  defmodule TestContract do
    use Perimeter.Contract

    defcontract :user do
      required :email, :string
      optional :address, :map do
        required :street, :string
        required :city, :string
      end
    end
  end

  contract = TestContract.__contract__(:user)
  address_field = Enum.find(contract.fields, & &1.name == :address)

  assert is_list(address_field.nested_fields)
  assert length(address_field.nested_fields) == 2
end
```

**Implementation**: Support nested block in optional/required macros

---

## Phase 2: Validation Engine (Week 2)

### Feature 2.1: Type Validation

**Test First**:
```elixir
# test/perimeter/validator_test.exs
defmodule Perimeter.ValidatorTest do
  use ExUnit.Case
  alias Perimeter.Validator

  defmodule TestContract do
    use Perimeter.Contract

    defcontract :types do
      required :name, :string
      required :age, :integer
      required :active, :boolean
      required :role, :atom
    end
  end

  test "validates correct types" do
    data = %{name: "Alice", age: 30, active: true, role: :admin}
    assert {:ok, validated} = Validator.validate(TestContract, :types, data)
    assert validated == data
  end

  test "rejects incorrect types" do
    data = %{name: 123, age: 30, active: true, role: :admin}
    assert {:error, violations} = Validator.validate(TestContract, :types, data)

    assert [%{field: :name, error: error}] = violations
    assert error =~ "expected string"
  end
end
```

**Implementation Order**:
1. Create `lib/perimeter/validator.ex`
2. Implement `validate/3` function
3. Implement type checking for: `:string`, `:integer`, `:boolean`, `:atom`, `:map`, `:list`
4. Create `Perimeter.ValidationError` struct

### Feature 2.2: Required Field Validation

**Test First**:
```elixir
test "validates required fields are present" do
  defmodule TestContract do
    use Perimeter.Contract

    defcontract :user do
      required :email, :string
      required :password, :string
    end
  end

  data = %{email: "test@example.com"}
  assert {:error, violations} = Validator.validate(TestContract, :user, data)

  assert [%{field: :password, error: "is required"}] = violations
end

test "allows missing optional fields" do
  defmodule TestContract do
    use Perimeter.Contract

    defcontract :user do
      required :email, :string
      optional :name, :string
    end
  end

  data = %{email: "test@example.com"}
  assert {:ok, _} = Validator.validate(TestContract, :user, data)
end
```

**Implementation**: Check field presence before type validation

### Feature 2.3: Constraint Validation

**Test First**:
```elixir
describe "string constraints" do
  test "validates format with regex" do
    defmodule TestContract do
      use Perimeter.Contract

      defcontract :user do
        required :email, :string, format: ~r/@/
      end
    end

    assert {:ok, _} = Validator.validate(TestContract, :user, %{email: "a@b.com"})
    assert {:error, _} = Validator.validate(TestContract, :user, %{email: "invalid"})
  end

  test "validates min_length" do
    defmodule TestContract do
      use Perimeter.Contract

      defcontract :user do
        required :password, :string, min_length: 8
      end
    end

    assert {:ok, _} = Validator.validate(TestContract, :user, %{password: "12345678"})
    assert {:error, _} = Validator.validate(TestContract, :user, %{password: "short"})
  end

  test "validates max_length" do
    defmodule TestContract do
      use Perimeter.Contract

      defcontract :user do
        required :name, :string, max_length: 10
      end
    end

    assert {:ok, _} = Validator.validate(TestContract, :user, %{name: "Alice"})
    assert {:error, _} = Validator.validate(TestContract, :user, %{name: "VeryLongName"})
  end
end

describe "integer constraints" do
  test "validates min" do
    defmodule TestContract do
      use Perimeter.Contract

      defcontract :user do
        required :age, :integer, min: 0
      end
    end

    assert {:ok, _} = Validator.validate(TestContract, :user, %{age: 25})
    assert {:error, _} = Validator.validate(TestContract, :user, %{age: -1})
  end

  test "validates max" do
    defmodule TestContract do
      use Perimeter.Contract

      defcontract :user do
        required :age, :integer, max: 150
      end
    end

    assert {:ok, _} = Validator.validate(TestContract, :user, %{age: 25})
    assert {:error, _} = Validator.validate(TestContract, :user, %{age: 200})
  end
end

describe "enum constraints" do
  test "validates value is in list" do
    defmodule TestContract do
      use Perimeter.Contract

      defcontract :user do
        required :role, :atom, in: [:admin, :user, :guest]
      end
    end

    assert {:ok, _} = Validator.validate(TestContract, :user, %{role: :admin})
    assert {:error, _} = Validator.validate(TestContract, :user, %{role: :invalid})
  end
end
```

**Implementation**: Constraint validation functions for each type

### Feature 2.4: Nested Map Validation

**Test First**:
```elixir
test "validates nested maps" do
  defmodule TestContract do
    use Perimeter.Contract

    defcontract :user do
      required :email, :string
      optional :address, :map do
        required :city, :string
        required :zip, :string, format: ~r/^\d{5}$/
      end
    end
  end

  data = %{
    email: "test@example.com",
    address: %{
      city: "Portland",
      zip: "97201"
    }
  }

  assert {:ok, _} = Validator.validate(TestContract, :user, data)
end

test "reports nested validation errors with path" do
  defmodule TestContract do
    use Perimeter.Contract

    defcontract :user do
      optional :address, :map do
        required :zip, :string, format: ~r/^\d{5}$/
      end
    end
  end

  data = %{address: %{zip: "invalid"}}
  assert {:error, violations} = Validator.validate(TestContract, :user, data)

  assert [%{field: :zip, path: [:address], error: _}] = violations
end
```

**Implementation**: Recursive validation with path tracking

### Feature 2.5: List Validation

**Test First**:
```elixir
test "validates list item types" do
  defmodule TestContract do
    use Perimeter.Contract

    defcontract :data do
      required :tags, {:list, :string}
    end
  end

  assert {:ok, _} = Validator.validate(TestContract, :data, %{tags: ["a", "b"]})
  assert {:error, _} = Validator.validate(TestContract, :data, %{tags: ["a", 123]})
end
```

**Implementation**: List item type validation

---

## Phase 3: Guard Macro (Week 3)

### Feature 3.1: Basic Guard Injection

**Test First**:
```elixir
# test/perimeter/guard_test.exs
defmodule Perimeter.GuardTest do
  use ExUnit.Case

  defmodule GuardedModule do
    use Perimeter

    defcontract :input do
      required :email, :string
    end

    @guard input: :input
    def create_user(params) do
      {:ok, params.email}
    end
  end

  test "allows valid input" do
    assert {:ok, "test@example.com"} =
      GuardedModule.create_user(%{email: "test@example.com"})
  end

  test "raises on invalid input" do
    assert_raise Perimeter.ValidationError, fn ->
      GuardedModule.create_user(%{email: 123})
    end
  end

  test "raises on missing required field" do
    assert_raise Perimeter.ValidationError, fn ->
      GuardedModule.create_user(%{})
    end
  end
end
```

**Implementation Order**:
1. Create `lib/perimeter/guard.ex`
2. Implement `use Perimeter.Guard` macro
3. Implement `@guard` attribute handling
4. Use `@before_compile` hook to inject validation
5. Wrap original function with validation logic

### Feature 3.2: Multiple Guards in One Module

**Test First**:
```elixir
test "supports multiple guarded functions" do
  defmodule MultiGuard do
    use Perimeter

    defcontract :create_input do
      required :email, :string
    end

    defcontract :update_input do
      required :id, :string
      optional :email, :string
    end

    @guard input: :create_input
    def create(params), do: {:ok, :created}

    @guard input: :update_input
    def update(params), do: {:ok, :updated}
  end

  assert {:ok, :created} = MultiGuard.create(%{email: "a@b.com"})
  assert {:ok, :updated} = MultiGuard.update(%{id: "123"})
end
```

**Implementation**: Track multiple guards via module attributes

### Feature 3.3: Clear Error Messages

**Test First**:
```elixir
test "provides clear error messages with field paths" do
  defmodule GuardedModule do
    use Perimeter

    defcontract :input do
      required :user, :map do
        required :email, :string, format: ~r/@/
      end
    end

    @guard input: :input
    def process(params), do: {:ok, params}
  end

  error = assert_raise Perimeter.ValidationError, fn ->
    GuardedModule.process(%{user: %{email: "invalid"}})
  end

  assert error.message =~ "Validation failed"
  assert error.violations == [
    %{field: :email, path: [:user], error: "does not match format"}
  ]
end
```

**Implementation**: Format validation errors into exception

### Feature 3.4: Preserves Function Metadata

**Test First**:
```elixir
test "preserves original function documentation" do
  defmodule DocumentedModule do
    use Perimeter

    defcontract :input do
      required :email, :string
    end

    @doc "Creates a new user"
    @guard input: :input
    def create_user(params), do: {:ok, params}
  end

  {:docs_v1, _, :elixir, _, %{"en" => module_doc}, _, functions} =
    Code.fetch_docs(DocumentedModule)

  {_, _, _, %{"en" => doc}, _} =
    Enum.find(functions, fn {{name, _}, _, _, _, _} -> name == :create_user end)

  assert doc == "Creates a new user"
end
```

**Implementation**: Preserve @doc and other attributes during wrapping

---

## Phase 4: Integration & Polish (Week 4)

### Feature 4.1: Main Module API

**Test First**:
```elixir
# test/perimeter_test.exs
defmodule PerimeterTest do
  use ExUnit.Case

  test "use Perimeter imports necessary modules" do
    defmodule TestModule do
      use Perimeter

      defcontract :test do
        required :field, :string
      end

      @guard input: :test
      def guarded(params), do: {:ok, params}
    end

    # Both contract and guard should work
    assert TestModule.__contract__(:test)
    assert {:ok, _} = TestModule.guarded(%{field: "value"})
  end
end
```

**Implementation**:
```elixir
# lib/perimeter.ex
defmodule Perimeter do
  defmacro __using__(_opts) do
    quote do
      use Perimeter.Contract
      use Perimeter.Guard
    end
  end
end
```

### Feature 4.2: Comprehensive Integration Tests

**Test First**:
```elixir
# test/perimeter/integration_test.exs
defmodule Perimeter.IntegrationTest do
  use ExUnit.Case

  describe "real-world scenario: user registration" do
    defmodule UserRegistration do
      use Perimeter

      defcontract :registration_params do
        required :email, :string, format: ~r/@/
        required :password, :string, min_length: 12
        optional :profile, :map do
          optional :name, :string, max_length: 100
          optional :age, :integer, min: 18, max: 150
        end
      end

      @guard input: :registration_params
      def register(params) do
        # Simulate user creation
        {:ok, %{
          id: "user_123",
          email: params.email,
          profile: Map.get(params, :profile, %{})
        }}
      end
    end

    test "successful registration with minimal fields" do
      result = UserRegistration.register(%{
        email: "user@example.com",
        password: "supersecret123"
      })

      assert {:ok, user} = result
      assert user.email == "user@example.com"
    end

    test "successful registration with profile" do
      result = UserRegistration.register(%{
        email: "user@example.com",
        password: "supersecret123",
        profile: %{name: "Alice", age: 30}
      })

      assert {:ok, user} = result
      assert user.profile.name == "Alice"
    end

    test "rejects invalid email" do
      assert_raise Perimeter.ValidationError, ~r/email.*format/, fn ->
        UserRegistration.register(%{
          email: "invalid-email",
          password: "supersecret123"
        })
      end
    end

    test "rejects short password" do
      assert_raise Perimeter.ValidationError, ~r/password.*min_length/, fn ->
        UserRegistration.register(%{
          email: "user@example.com",
          password: "short"
        })
      end
    end

    test "rejects underage user" do
      assert_raise Perimeter.ValidationError, ~r/age.*min/, fn ->
        UserRegistration.register(%{
          email: "user@example.com",
          password: "supersecret123",
          profile: %{age: 17}
        })
      end
    end
  end

  describe "real-world scenario: API request handling" do
    defmodule APIHandler do
      use Perimeter

      defcontract :search_params do
        required :query, :string, min_length: 1
        optional :filters, :map do
          optional :category, :atom, in: [:all, :active, :archived]
          optional :limit, :integer, min: 1, max: 100
        end
      end

      @guard input: :search_params
      def search(params) do
        query = params.query
        filters = Map.get(params, :filters, %{})

        {:ok, %{
          query: query,
          category: Map.get(filters, :category, :all),
          limit: Map.get(filters, :limit, 10)
        }}
      end
    end

    test "search with defaults" do
      assert {:ok, result} = APIHandler.search(%{query: "test"})
      assert result.category == :all
      assert result.limit == 10
    end

    test "search with custom filters" do
      result = APIHandler.search(%{
        query: "test",
        filters: %{category: :active, limit: 50}
      })

      assert {:ok, %{category: :active, limit: 50}} = result
    end

    test "rejects invalid category" do
      assert_raise Perimeter.ValidationError, fn ->
        APIHandler.search(%{
          query: "test",
          filters: %{category: :invalid}
        })
      end
    end
  end
end
```

### Feature 4.3: Documentation Examples

**All @doc examples should be executable via doctest**:

```elixir
# In lib/perimeter/contract.ex
@doc """
Defines a type contract.

## Examples

    defmodule MyModule do
      use Perimeter.Contract

      defcontract :user do
        required :email, :string, format: ~r/@/
        optional :name, :string
      end
    end

    iex> MyModule.__contract__(:user)
    %Perimeter.Contract{...}
"""
defmacro defcontract(name, do: block)
```

**Enable doctest**:
```elixir
# test/perimeter/contract_test.exs
defmodule Perimeter.ContractTest do
  use ExUnit.Case
  doctest Perimeter.Contract

  # ... rest of tests
end
```

---

## Implementation Schedule

### Week 1: Contract Definition
- **Day 1-2**: Setup + Contract struct + basic macros
- **Day 3-4**: Field definitions (required/optional)
- **Day 5**: Nested contracts + constraints storage

### Week 2: Validation Engine
- **Day 1-2**: Type validation (all basic types)
- **Day 3**: Constraint validation (format, min/max, in:)
- **Day 4**: Nested validation + error paths
- **Day 5**: List validation + error formatting

### Week 3: Guard Macro
- **Day 1-2**: Basic guard injection
- **Day 3**: Multiple guards support
- **Day 4**: Error handling + clear messages
- **Day 5**: Preserve metadata + edge cases

### Week 4: Integration & Documentation
- **Day 1**: Main module + comprehensive integration tests
- **Day 2**: Documentation with doctests
- **Day 3**: README with real examples
- **Day 4**: Final polish + edge case testing
- **Day 5**: Review + prepare for v0.1.0 release

---

## Definition of Done

Each feature is "done" when:
- ✅ Tests written first (TDD)
- ✅ Tests pass
- ✅ Code documented with @doc
- ✅ Doctests pass
- ✅ No compiler warnings
- ✅ Integration test covers feature

MVP is "done" when:
- ✅ All 15 features implemented
- ✅ All tests pass
- ✅ Test coverage > 90%
- ✅ README has working examples
- ✅ Can dogfood: Perimeter validates its own API
- ✅ ExDoc generates clean documentation

---

## Testing Principles

1. **Test behavior, not implementation**
2. **Each test should test one thing**
3. **Test names should describe the behavior**
4. **Use descriptive assertions**
5. **Setup only what's needed for each test**
6. **Keep tests independent**

---

## Next Steps

1. Review and approve this plan
2. Set up test infrastructure
3. Start with Week 1, Day 1: Contract struct
4. Follow TDD cycle religiously
5. Daily standup: what test am I writing next?

**Are you ready to begin implementation?**
