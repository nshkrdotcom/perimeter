<div align="center">
  <img src="assets/logo.svg" alt="Perimeter Logo" width="200" height="200">
</div>

# Perimeter

**An implementation of the "Defensive Perimeter / Offensive Interior" design pattern for Elixir.**

Perimeter helps you build robust and maintainable applications by enforcing explicit data contracts at your system's perimeters. This allows you to write simple, assertive, and highly dynamic code in your core logic with confidence.

## Installation

**Note**: This package is not yet published to Hex. To use it, add it as a Git dependency:

```elixir
def deps do
  [
    {:perimeter, github: "nshkrdotcom/perimeter"}
  ]
end
```

## Quick Start

```elixir
defmodule MyApp.Accounts do
  use Perimeter

  # 1. Define a contract for your data
  defcontract :create_user do
    required :email, :string, format: ~r/@/
    required :password, :string, min_length: 12
    optional :name, :string, max_length: 100
  end

  # 2. Guard your function with the contract
  @guard input: :create_user
  def create_user(params) do
    # 3. Write simple, assertive code - params are guaranteed valid!
    {:ok, %{
      email: params.email,
      name: Map.get(params, :name, "Anonymous")
    }}
  end
end

# Valid input
MyApp.Accounts.create_user(%{
  email: "user@example.com",
  password: "supersecret123"
})
# => {:ok, %{email: "user@example.com", name: "Anonymous"}}

# Invalid input raises with clear error message
MyApp.Accounts.create_user(%{email: "invalid", password: "short"})
# => ** (Perimeter.ValidationError) Validation failed at perimeter with 2 violation(s):
#      - email: does not match format
#      - password: must be at least 12 characters (minimum length)
```

## The Problem: Defensive Coding Everywhere

In any large system, modules need to exchange data. This often leads to defensive coding throughout your codebase:

```elixir
def create_user(params) do
  # Defensive checks everywhere
  case get_in(params, ["user", "email"]) do
    nil -> {:error, :email_required}
    email when is_binary(email) ->
      case validate_email_format(email) do
        :ok ->
          case get_in(params, ["user", "password"]) do
            nil -> {:error, :password_required}
            password when byte_size(password) >= 12 ->
              # Finally, our actual logic!
              do_create_user(email, password)
            _ -> {:error, :password_too_short}
          end
        :error -> {:error, :invalid_email}
      end
    _ -> {:error, :invalid_email_type}
  end
end
```

This code is:
- ❌ **Verbose**: Validation mixed with business logic
- ❌ **Error-prone**: Easy to forget checks or get them wrong
- ❌ **Hard to maintain**: Changes require updating validation logic scattered everywhere
- ❌ **Not reusable**: Same validations duplicated across functions

## The Solution: Defensive Perimeter / Offensive Interior

Perimeter implements a three-zone architecture:

```
┌─────────────────────────────────────────┐
│       DEFENSIVE PERIMETER (@guard)      │
│   ┌─────────────────────────────────┐   │
│   │    TRANSITION LAYER (validate)  │   │
│   │  ┌───────────────────────────┐  │   │
│   │  │  OFFENSIVE INTERIOR       │  │   │
│   │  │  (your business logic)    │  │   │
│   │  └───────────────────────────┘  │   │
│   └─────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

1. **Defensive Perimeter**: Guards validate all inputs before they enter your function
2. **Transition Layer**: Automatic normalization and transformation
3. **Offensive Interior**: Your business logic with guaranteed-valid data

## Features

### Comprehensive Type System

- ✅ Basic types: `:string`, `:integer`, `:float`, `:boolean`, `:atom`, `:map`, `:list`
- ✅ Typed lists: `{:list, :string}`, `{:list, :integer}`, etc.
- ✅ Nested maps with full validation
- ✅ Required and optional fields

### Rich Constraint System

**String constraints:**
```elixir
required :email, :string, format: ~r/@/
required :username, :string, min_length: 3, max_length: 20
```

**Number constraints:**
```elixir
required :age, :integer, min: 18, max: 150
required :price, :float, min: 0.0
```

**Enum constraints:**
```elixir
required :role, :atom, in: [:admin, :user, :guest]
required :status, :string, in: ["active", "inactive"]
```

### Nested Validation

```elixir
defcontract :user do
  required :email, :string
  optional :address, :map do
    required :city, :string
    required :zip, :string, format: ~r/^\d{5}$/
    optional :state, :string
  end
end
```

### Clear Error Messages

```elixir
MyApp.Accounts.create_user(%{
  email: "invalid",
  password: "short",
  profile: %{age: 17}
})
# ** (Perimeter.ValidationError) Validation failed at perimeter with 3 violation(s):
#   - email: does not match format
#   - password: must be at least 12 characters (minimum length)
#   - profile.age: must be >= 18 (minimum value)
```

## Real-World Examples

### API Request Handling

```elixir
defmodule MyAPI.SearchController do
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
    # params.query, params.filters are guaranteed valid
    MyApp.Search.run(params.query, Map.get(params, :filters, %{}))
  end
end
```

### Configuration Validation

```elixir
defmodule MyApp.Config do
  use Perimeter

  defcontract :database_config do
    required :host, :string
    required :port, :integer, min: 1, max: 65535
    required :database, :string
    optional :pool_size, :integer, min: 1, max: 100
  end

  @guard input: :database_config
  def connect(config) do
    # config is validated - safe to use directly
    Ecto.Repo.start_link(
      hostname: config.host,
      port: config.port,
      database: config.database,
      pool_size: Map.get(config, :pool_size, 10)
    )
  end
end
```

### Data Processing Pipelines

```elixir
defmodule MyApp.DataProcessor do
  use Perimeter

  defcontract :process_input do
    required :items, {:list, :map}
    required :operation, :atom, in: [:transform, :filter, :aggregate]
    optional :batch_size, :integer, min: 1, max: 1000
  end

  @guard input: :process_input
  def process(params) do
    params.items
    |> Enum.chunk_every(Map.get(params, :batch_size, 100))
    |> Enum.map(&apply_operation(&1, params.operation))
  end
end
```

## Documentation

### Core Modules

- **`Perimeter`** - Main module, use with `use Perimeter`
- **`Perimeter.Contract`** - Define contracts with `defcontract`
- **`Perimeter.Guard`** - Apply guards with `@guard`
- **`Perimeter.Validator`** - Manual validation API
- **`Perimeter.ValidationError`** - Exception raised on validation failure

### Design Documentation

For a deeper understanding of the philosophy and design:

- [Design Philosophy and Principles](docs/PERIMETER_gem_0010.md) - The "why" behind the library
- [Type Perimeters Design](docs/type_perimeters_design.md) - The core innovation
- [Implementation Guide](docs/PERIMETER_LIBRARY_IMPLEMENTATION_GUIDE.md) - Comprehensive reference

## Testing

Perimeter has comprehensive test coverage:

```bash
mix test
# => 117 tests, 0 failures
```

Test categories:
- **Contract tests** (16 tests) - Contract definition and structure
- **Validator tests** (47 tests) - Validation logic and constraints
- **Guard tests** (26 tests) - Function perimeter enforcement
- **Integration tests** (26 tests) - Real-world scenarios
- **Doctests** (1 test) - Documentation examples

## Solving Common Elixir Anti-Patterns

Perimeter is designed to programmatically guide you away from common Elixir anti-patterns, leading to cleaner and more maintainable code.

| Anti-Pattern                      | How Perimeter Solves It                                                                                              |
| :-------------------------------- | :------------------------------------------------------------------------------------------------------------------- |
| **Non-Assertive Map Access**      | Contracts guarantee the shape of data, allowing you to use assertive `map.key` and `%{key: val}` access.              |
| **Dynamic Atom Creation**         | Contracts validate incoming strings against an explicit list of allowed values, which can then be safely converted to existing atoms. |
| **Complex `else` Clauses in `with`** | Promotes a single, clear validation step at the beginning of a function, simplifying "happy path" logic.          |
| **Non-Assertive Pattern Matching**  | By validating the data shape at the perimeter, you can write assertive, non-defensive code in the function interior. |

Read the full list of anti-patterns Perimeter helps address in [**ELIXIR_1_20_0_DEV_ANTIPATTERNS.md**](docs/ELIXIR_1_20_0_DEV_ANTIPATTERNS.md).

## Full Documentation

This library is the result of extensive research and design. The complete documentation, from initial problem analysis to the final architectural blueprint, is available for review.

### Core Design and Philosophy

*   [**Design Philosophy and Principles**](docs/PERIMETER_gem_0010.md) - The "why" behind the library, inspired by Elixir's core tenets.
*   [**Type Perimeters Design**](docs/type_perimeters_design.md) - The original "Defensive Perimeter / Offensive Interior" concept.
*   [**Greenfield Architecture Guide**](docs/PERIMETER_gem_0012.md) - A blueprint for architecting new applications with Perimeter.

### Implementation and Usage Guides

*   [**Implementation Guide**](docs/PERIMETER_LIBRARY_IMPLEMENTATION_GUIDE.md) - A comprehensive guide to the library's internal structure.
*   [**Migration Strategy Guide**](docs/migration_strategy_guide.md) - How to adopt Perimeter in an existing "brownfield" application.
*   [**Defensive Perimeter Implementation**](docs/defensive_perimeter_implementation.md) - Practical code patterns for implementing the core concepts.
*   [**Type-Safe Metaprogramming Patterns**](docs/type_safe_metaprogramming_patterns.md) - How to safely combine Perimeter with Elixir's metaprogramming features.

### Best Practices and Specifications

*   [**Type Contract Best Practices**](docs/type_contract_best_practices.md) - Dos and Don'ts for writing effective contracts.
*   [**Error Handling and Type Safety**](docs/error_handling_type_safety.md) - Patterns for robust error handling at perimeters.
*   [**Formal Type Relationships Spec**](docs/type_relationships_formal_spec.md) - A formal specification of the type system.
*   [**Type Enforcement Library Spec**](docs/type_enforcement_library_spec.md) - The detailed API specification for the library.
*   [**Perimeter Caching Strategies**](docs/PERIMETER_CACHING_STRATEGIES.md) - A plan for ensuring high performance.

### Project Planning

*   [**Project Roadmap**](docs/PERIMETER_gem_0011.md)
*   [**Implementation Prompts**](docs/PERIMETER_LIBRARY_IMPLEMENTATION_PROMPTS.md)

## Contributing

Contributions are welcome! This project is in the planning phase, and feedback on the design is highly encouraged. Please see our contribution guidelines and code of conduct. (Links to be added).
