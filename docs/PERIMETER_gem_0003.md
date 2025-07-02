Excellent. Let's continue by creating the final two key documents for the library: a guide on **Best Practices and Anti-Patterns** and a guide for **Testing**. These documents will solidify the library's philosophy and provide users with actionable advice for success.

---

### `guides/best_practices.md`

# Best Practices & Anti-Patterns

This guide covers recommended best practices for using the `Perimeter` library effectively. Following these patterns will help you write code that is clear, maintainable, and robust, while avoiding common pitfalls.

This guide is a practical application of the principles found in the [Type Contract Best Practices document (20250702)](../../docs20250702/type_contract_best_practices.md).

## Table of Contents

1.  [Contract Best Practices](#1-contract-best-practices)
    *   Be Explicit and Semantic
    *   Compose, Don't Repeat
    *   Separate Validation from Business Logic
2.  [Guard Best Practices](#2-guard-best-practices)
    *   Guard at the System Boundary
    *   Trust the Interior
3.  [Common Anti-Patterns to Avoid](#3-common-anti-patterns-to-avoid)
    *   Anti-Pattern: The Chain of Guards
    *   Anti-Pattern: The Overly-Complex Custom Validator
    *   Anti-Pattern: The Anemic Contract
    *   Anti-Pattern: Bypassing the Guard

## 1. Contract Best Practices

### Be Explicit and Semantic

Your contracts are executable documentation. They should clearly communicate the intent and structure of your data.

**DO:** Use clear, domain-specific names for fields and contracts.

```elixir
# Good: Clear, semantic, and documents the business rule.
defcontract :user_registration do
  required :email_address, :string, format: ~r/@/
  required :password_hash, :string, min_length: 12
  required :agreed_to_terms_at, :utc_datetime
end
```

**DON'T:** Use abbreviated or generic names that hide meaning.

```elixir
# Bad: Ambiguous and unhelpful.
defcontract :data do
  required :f1, :string
  required :f2, :string
  required :f3, :datetime
end
```

### Compose, Don't Repeat

If you find yourself defining the same set of fields in multiple contracts, extract them into a shared, reusable contract and compose them.

**DO:** Create small, reusable contracts for common data structures like timestamps or pagination.

```elixir
defmodule MyApp.SharedContracts do
  use Perimeter.Contract

  defcontract :timestamps do
    required :inserted_at, :utc_datetime
    required :updated_at, :utc_datetime
  end

  defcontract :pagination_params do
    optional :page, :integer, min: 1, default: 1
    optional :per_page, :integer, min: 1, max: 100, default: 25
  end
end

defmodule MyApp.UserContracts do
  use Perimeter.Contract
  import MyApp.SharedContracts

  # Compose the shared contract
  defcontract :user_output do
    required :id, :string
    required :email, :string
    compose :timestamps
  end
end
```

**DON'T:** Copy and paste field definitions across multiple contracts. This leads to maintenance headaches when a shared field needs to be changed.

### Separate Validation from Business Logic

A contract's job is to validate the **shape and integrity** of data, not to perform business operations.

**DO:** Keep custom validators focused on pure data validation.

```elixir
# Good: The validator checks a pure data constraint.
defcontract :booking do
  required :start_date, :date
  required :end_date, :date

  validate :dates_are_sequential
end

defp dates_are_sequential(%{start_date: s, end_date: e}) do
  if Date.compare(e, s) == :gt, do: :ok, else: {:error, ...}
end
```

**DON'T:** Put complex business logic, database calls, or external API requests inside a custom validator. This makes your contracts slow, impure, and hard to test.

```elixir
# Bad: This validator is performing business logic.
defcontract :order do
  required :items, {:list, :map}
  validate :check_inventory_levels_in_db # Don't do this!
end

# The correct approach is to do this check in your business logic
# AFTER the contract has been validated.
@guard input: :order
def place_order(params) do
  # The contract has validated the shape of `params`.
  # Now, perform the business logic checks.
  with :ok <- check_inventory(params.items) do
    # ...
  end
end
```

## 2. Guard Best Practices

### Guard at the System Boundary

The most effective place to use `@guard` is at the entry points of your application or context. This creates the "Defensive Perimeter."

**DO:** Place guards on:
*   Phoenix Controller actions.
*   The public API functions of your core contexts (e.g., `Accounts.create_user/1`).
*   GenServer `handle_call`/`handle_cast` functions, or the public API that calls them.
*   The entry point for background job processors.

### Trust the Interior

Once a function call has passed through a guard, **trust the data**. The whole point of the "Offensive Interior" is that you can write assertive, non-defensive code.

**DO:** Use assertive pattern matching and access inside a guarded function.

```elixir
@guard input: :user_with_profile
def process_user(user) do
  # We know `user` is valid. We can be assertive.
  # This is much clearer than `get_in` or defensive checks.
  %{email: email, profile: %{name: name}} = user

  Logger.info("Processing user #{name} with email #{email}")
end
```

**DON'T:** Re-validate data that has already been validated by a guard. This is redundant and defeats the purpose of the pattern.

```elixir
# Bad: Redundant, defensive check.
@guard input: :user_with_profile
def process_user(user) do
  # The guard already confirmed `profile` is a map. This is unnecessary.
  if is_map(user.profile) do
    # ...
  end
end
```

## 3. Common Anti-Patterns to Avoid

### Anti-Pattern: The Chain of Guards

Calling a guarded function from within another guarded function can be a sign of a design flaw. It often means you are performing validation too deep inside your system.

```elixir
# Anti-pattern: Chained guards
defmodule A do
  use Perimeter
  defcontract :a_contract, do: #...
  
  @guard input: :a_contract
  def process(params) do
    B.process(params) # B.process is also guarded
  end
end

defmodule B do
  use Perimeter
  defcontract :b_contract, do: #...

  @guard input: :b_contract
  def process(params) do
    #...
  end
end
```

**Solution:** Guard only the outermost function (`A.process/1`). Module `B` should assume it receives valid data and not have its own guard. Create a clear "public" interface for your context, and only guard that. Internal functions should trust their inputs.

### Anti-Pattern: The Overly-Complex Custom Validator

If your custom validator function is more than a few lines long and contains complex `case` or `cond` statements, it's a sign that you are mixing business logic with validation.

**Solution:** Break the logic out. Create a contract that validates the basic data types. Then, in a separate function (or the main body of the guarded function), perform the more complex business rule validation.

### Anti-Pattern: The Anemic Contract

A contract that only checks for the existence of keys without checking their types is not providing much safety.

```elixir
# Bad: This allows `%{user_id: "not-an-integer"}` to pass.
defcontract :anemic do
  required :user_id, :any
end
```

**Solution:** Be as specific as possible with types and constraints. The more specific your contract, the more safety you get.

```elixir
# Good: Provides strong guarantees about the data.
defcontract :robust do
  required :user_id, :integer, min: 1
end
```

### Anti-Pattern: Bypassing the Guard

It can be tempting to call an internal, unguarded version of a function to "skip" validation. This breaks the security model of the Defensive Perimeter.

```elixir
# Anti-pattern
defmodule MyContext do
  use Perimeter
  
  defcontract :create_params, do: #...

  @guard input: :create_params
  def create_user(params), do: do_create_user(params)

  # Other functions in the app start calling this directly
  # to bypass validation. This is dangerous!
  def do_create_user(params) do
    # ...
  end
end
```

**Solution:** Make the unguarded function private (`defp`). This forces all external callers to go through the public, guarded function, ensuring that the contract is always enforced at the boundary.

---

### `guides/testing_guide.md`

# Testing with Perimeter

Testing is a critical part of a contract-driven workflow. `Perimeter` is designed to be highly testable and to make your application tests more robust.

## Table of Contents

1.  [Testing Your Contracts](#1-testing-your-contracts)
    *   Using `Perimeter.validate/2`
    *   A Simple Contract Test Helper
2.  [Testing Guarded Functions](#2-testing-guarded-functions)
    *   Testing the "Happy Path"
    *   Testing Validation Failures
3.  [Testing with Different Enforcement Levels](#3-testing-with-different-enforcement-levels)

## 1. Testing Your Contracts

Since contracts are central to your application's correctness, it's a good practice to write tests for the contracts themselves, especially complex ones with custom validators.

You can test a contract directly using `Perimeter.validate/2`.

### Using `Perimeter.validate/2`

The `Perimeter.validate/2` function allows you to invoke contract validation outside of a guard. It takes the module where the contract is defined and the contract name.

```elixir
defmodule MyApp.UserContractsTest do
  use ExUnit.Case
  alias MyApp.UserContracts

  describe "user_registration contract" do
    test "succeeds with valid data" do
      valid_data = %{
        email_address: "test@example.com",
        password_hash: "a-very-secure-hash-123",
        agreed_to_terms_at: DateTime.utc_now()
      }

      assert {:ok, _} = Perimeter.validate(UserContracts, :user_registration, valid_data)
    end

    test "fails when email is invalid" do
      invalid_data = %{
        email_address: "not-an-email",
        password_hash: "a-very-secure-hash-123",
        agreed_to_terms_at: DateTime.utc_now()
      }

      expected_error =
        {:error,
         %Perimeter.Error{
           violations: [
             %{field: :email_address, error: "has invalid format"}
           ]
         }}

      # Use pattern matching for a more robust assertion
      assert {:error, %Perimeter.Error{violations: [%{field: :email_address}]}} =
               Perimeter.validate(UserContracts, :user_registration, invalid_data)
    end
  end
end
```

### A Simple Contract Test Helper

You can create simple test helpers to make your contract tests more concise.

```elixir
# test/support/contract_case.ex
defmodule MyApp.ContractCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import MyApp.ContractCase
    end
  end

  def assert_contract_ok(module, contract, data) do
    case Perimeter.validate(module, contract, data) do
      {:ok, _} -> :ok
      {:error, error} -> flunk("Expected contract to be valid, but got error: #{inspect(error)}")
    end
  end

  def assert_contract_error(module, contract, data, expected_field) do
    case Perimeter.validate(module, contract, data) do
      {:error, %Perimeter.Error{violations: violations}} ->
        assert Enum.any?(violations, &(&1.field == unquote(expected_field))),
               "Expected an error for field `#{unquote(expected_field)}` but didn't find one."
      {:ok, _} ->
        flunk("Expected contract to be invalid, but it was valid.")
    end
  end
end

# In your test:
defmodule MyApp.UserContractsTest do
  use MyApp.ContractCase # Use your custom case template

  alias MyApp.UserContracts

  test "succeeds with valid data" do
    valid_data = %{email_address: "test@example.com", ...}
    assert_contract_ok(UserContracts, :user_registration, valid_data)
  end

  test "fails with bad email" do
    invalid_data = %{email_address: "bad", ...}
    assert_contract_error(UserContracts, :user_registration, invalid_data, :email_address)
  end
end
```

## 2. Testing Guarded Functions

When testing a module that uses `@guard`, you are typically testing two things: how it behaves with valid data, and how it behaves with invalid data.

### Testing the "Happy Path"

This is your standard test case. You provide valid data and assert that the function returns the expected success value. The guard is implicitly tested because the function executes as expected.

```elixir
defmodule MyApp.Actions.CreateUserTest do
  use ExUnit.Case
  alias MyApp.Actions.CreateUser

  test "creates a user with valid params" do
    valid_params = %{email: "test@example.com"}

    # The guard will validate `valid_params` and allow the function to run.
    assert {:ok, %{user: %User{email: "test@example.com"}}} =
             CreateUser.run(valid_params, %{})
  end
end
```

### Testing Validation Failures

To test the guard's failure case, provide invalid data and assert that the function returns a `Perimeter.Error`. Because your `test` environment is configured for `:strict` enforcement, the guard will immediately return an error without executing the function body.

```elixir
test "returns a validation error for invalid params" do
  invalid_params = %{email: "not-valid"} # Missing the @ symbol

  # The guard will reject the params and return a Perimeter.Error
  assert {:error, %Perimeter.Error{violations: violations}} =
           CreateUser.run(invalid_params, %{})

  # You can make your assertion more specific
  assert Enum.any?(violations, &(&1.field == :email))
end
```

This is a powerful way to test your boundaries. You don't need to mock anything; you are directly testing the contract enforcement that will happen in production.

## 3. Testing with Different Enforcement Levels

Sometimes you may want to test the behavior of a function when a guard is set to a non-strict level like `:warn`. You can use `Application.put_env/3` to temporarily change the enforcement level for a specific test.

**Note:** This is an advanced use case. Most of the time, you should test with `:strict` enforcement.

```elixir
test "logs a warning but still executes when enforcement is :warn" do
  # Temporarily set the enforcement level for this test only
  Application.put_env(:perimeter, :enforcement_level, :warn, persistent: true)

  invalid_params = %{email: "not-valid"}

  # Use ExUnit.CaptureLog to assert that a warning was logged.
  assert_logged "[warn] Perimeter contract violation" ->
    # The function body will still execute and likely raise an error
    # or return a different error tuple because the data is bad.
    # The exact result depends on the function's implementation.
    assert {:error, :some_internal_error} = CreateUser.run(invalid_params, %{})
  end

  # It's good practice to restore the original config after the test,
  # though ExUnit's sandboxing often handles this.
  Application.put_env(:perimeter, :enforcement_level, :strict, persistent: true)
end
```
