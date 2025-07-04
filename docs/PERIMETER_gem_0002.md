Excellent. The next logical document is a detailed **Usage Guide**. This guide will go beyond the `README.md` quick start, providing a step-by-step walkthrough of the library's core features, configuration, and practical application in different scenarios.

This document will be created as `guides/usage_guide.md` within the library's file structure.

---

### `guides/usage_guide.md`

# Perimeter Usage Guide

Welcome to the Perimeter Usage Guide! This document provides a comprehensive walkthrough of the library's features, from initial configuration to advanced contract definition and error handling. For the philosophy behind Perimeter, please see the main `README.md`.

## Table of Contents

1.  [Configuration](#1-configuration)
    *   Enforcement Levels
    *   Environment-Specific Configuration
    *   Overriding Enforcement
2.  [Defining Contracts in Detail](#2-defining-contracts-in-detail)
    *   Field Types and Validators
    *   Nested Contracts
    *   Custom Validations
3.  [Guarding Functions](#3-guarding-functions)
    *   Guarding Inputs and Outputs
    *   How Guards Interact with Function Clauses
4.  [Handling Violations](#4-handling-violations)
    *   The `Perimeter.Error` Struct
    *   Integrating with a Phoenix FallbackController
5.  [Advanced Use Case: Guarding a GenServer](#5-advanced-use-case-guarding-a-genserver)

## 1. Configuration

Perimeter's behavior is configured primarily through **enforcement levels**. This allows you to tailor how strictly contracts are enforced in different environments.

### Enforcement Levels

*   `:strict` (Default): If a contract is violated, the guarded function is **not** executed, and `{:error, %Perimeter.Error{}}` is returned immediately. **Recommended for `test` and `dev` environments.**
*   `:warn`: If a contract is violated, a warning is logged to the console, but the original function **is still executed** with the invalid data. This is useful for introducing Perimeter into an existing codebase without breaking functionality.
*   `:log`: Same as `:warn`, but logs at the `:info` level. Useful for monitoring contract adherence in production without generating excessive noise.

### Environment-Specific Configuration

You can set the global default enforcement level in your `config/config.exs` files.

```elixir
# config/config.exs
# Set a safe default for production.
config :perimeter,
  enforcement_level: :log

# config/dev.exs
# Be strict during development to catch issues early.
config :perimeter,
  enforcement_level: :strict

# config/test.exs
# Always be strict in tests.
config :perimeter,
  enforcement_level: :strict
```

### Overriding Enforcement

You can override the global default for a specific guard using the `:enforcement` option. This is useful for gradually rolling out stricter validation on a per-function basis.

```elixir
defmodule MyApp.LegacyModule do
  use Perimeter

  defcontract :some_data do
    required :id, :integer
  end

  # Even if the global default is :strict, this guard will only log violations.
  @guard input: :some_data, enforcement: :log
  def process_legacy_data(data) do
    # ...
  end
end
```

## 2. Defining Contracts in Detail

Contracts are the heart of Perimeter. They are defined using the `defcontract/2` macro.

### Field Types and Validators

Perimeter provides a rich set of built-in types and validators.

```elixir
defcontract :advanced_contract do
  # Basic types
  required :status, :atom, in: [:active, :pending, :archived]
  required :is_admin, :boolean
  required :priority, :integer, min: 1, max: 5
  required :name, :string, min_length: 2, max_length: 100
  required :email, :string, format: ~r/@/

  # Default values for optional fields
  optional :role, :string, default: "guest"
  optional :retries, :integer, default: 0

  # List validation
  required :tags, {:list, :string}, min_items: 1
  optional :scores, {:list, :integer}
end
```

### Nested Contracts

You can easily define contracts for nested maps and lists of maps.

```elixir
defcontract :order do
  required :order_id, :string
  
  # A nested map contract
  required :customer, :map do
    required :id, :integer
    optional :name, :string
  end

  # A list of nested maps
  required :line_items, {:list, :map}, min_items: 1 do
    required :product_id, :string
    required :quantity, :integer, min: 1
    required :price_cents, :integer, min: 0
  end
end
```

### Custom Validations

For complex business rules, you can add custom validation functions using `validate/1`. The function receives the (partially) validated data and must return `:ok` or an `{:error, details}` tuple.

```elixir
defcontract :event_registration do
  required :start_date, :date
  required :end_date, :date

  # Register a custom validator function
  validate :end_date_after_start_date
end

# The validator function must be defined in the same module.
defp end_date_after_start_date(%{start_date: start, end_date: end}) do
  if Date.compare(end, start) in [:gt, :eq] do
    :ok
  else
    # The error map is passed directly to Perimeter.Error
    {:error, %{field: :end_date, error: "must be on or after the start date"}}
  end
end
```

## 3. Guarding Functions

The `@guard` attribute is the mechanism that enforces your contracts.

### Guarding Inputs and Outputs

*   The `:input` option validates the **first argument** of the function.
*   The `:output` option validates the **return value** of the function.

```elixir
defmodule MyApp.Actions.CreateUser do
  use Perimeter

  # Contract for function input
  defcontract :input do
    required :email, :string
  end

  # Contract for the :ok part of the function output
  defcontract :success_output do
    required :user, MyApp.User
    required :id, :string
  end

  @guard input: :input, output: :success_output
  def run(params, _context) do
    # `params` is guaranteed to match the :input contract.
    case Accounts.create_user(params) do
      {:ok, user} ->
        # This return value will be validated against :success_output
        {:ok, %{user: user, id: user.id}}
      
      {:error, _changeset} = error ->
        # Error tuples are not validated and are passed through.
        error
    end
  end
end
```

### How Guards Interact with Function Clauses

Perimeter guards the function as a whole (`function/arity`). It does not guard individual function clauses. The guard runs **before** any of your function clauses are matched.

This means you can rely on the data structure being valid *before* you pattern match on it.

```elixir
# This contract ensures the `event` key exists and is an atom.
defcontract :event_payload do
  required :event, :atom
  optional :data, :map
end

@guard input: :event_payload
def handle_event(%{event: :user_created, data: user_data}) do
  # This clause will be safely matched for :user_created events.
end

@guard input: :event_payload
def handle_event(%{event: :order_shipped, data: order_data}) do
  # This clause will be safely matched for :order_shipped events.
end

@guard input: :event_payload
def handle_event(_payload) do
  # A catch-all for other valid events.
end
```

## 4. Handling Violations

When a contract is violated in `:strict` mode, your function returns `{:error, %Perimeter.Error{}}`.

### The `Perimeter.Error` Struct

The error struct gives you detailed information about what went wrong.

```elixir
%Perimeter.Error{
  type: :validation_error,
  message: "Input validation failed",
  violations: [
    %{
      field: :email,
      error: "is not a valid string",
      value: 123,
      path: [:user, :email] # The path to the invalid field
    },
    %{
      field: :age,
      error: "must be at least 18",
      value: 17,
      path: [:user, :profile, :age]
    }
  ]
}
```

### Integrating with a Phoenix FallbackController

A `FallbackController` is the idiomatic way to handle errors in a Phoenix JSON API. It's a perfect place to catch `Perimeter.Error` and transform it into a 422 Unprocessable Entity response.

```elixir
# lib/my_app_web/controllers/fallback_controller.ex
defmodule MyAppWeb.FallbackController do
  use MyAppWeb, :controller
  alias Perimeter.Error

  # This clause will catch errors from guarded controller actions.
  def call(conn, {:error, %Error{violations: violations}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: MyAppWeb.ErrorJSON)
    |> render("422.json", errors: format_violations(violations))
  end

  # Fallback for other errors
  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: MyAppWeb.ErrorJSON)
    |> render("404.json", %{})
  end

  # Helper to format violations for the API response
  defp format_violations(violations) do
    for violation <- violations do
      %{
        path: Enum.join(violation.path, "."),
        message: "#{violation.field} #{violation.error}",
        details: "Received value: #{inspect(violation.value)}"
      }
    end
  end
end
```

Then, in your router, tell your API pipeline to use this controller for errors.

```elixir
# lib/my_app_web/router.ex
pipeline :api do
  plug :accepts, ["json"]
  # Add this line to your API pipeline
  plug :action, fallback: MyAppWeb.FallbackController
end
```

## 5. Advanced Use Case: Guarding a GenServer

Perimeter isn't just for web requests. It's a powerful tool for ensuring the internal consistency of stateful processes like GenServers.

```elixir
defmodule MyApp.MetricsServer do
  use GenServer
  use Perimeter

  # Define a contract for the GenServer's state.
  defcontract :state do
    required :status, :atom, in: [:running, :paused]
    required :request_count, :integer, min: 0
    required :error_rates, :map
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    initial_state = %{status: :running, request_count: 0, error_rates: %{}}
    {:ok, initial_state}
  end

  # --- Public API ---

  defcontract :record_request_params do
    required :path, :string
    required :status_code, :integer
  end

  @guard input: :record_request_params
  def record_request(params) do
    # The `params` are validated before the GenServer call.
    GenServer.cast(__MODULE__, {:record_request, params})
  end

  # --- Server Callbacks ---

  # Guard the state argument in `handle_cast` to ensure it's always valid.
  @guard input: :state
  @impl true
  def handle_cast({:record_request, params}, state) do
    # We can trust that `state` is valid.
    new_state =
      state
      |> Map.update!(:request_count, &(&1 + 1))
      |> update_error_rate(params)

    # Returning a new state from here will NOT be automatically validated,
    # so we should be careful. Or, we can validate it manually.
    {:noreply, new_state}
  end

  # Guard for a call to ensure a valid state before replying.
  @guard input: :state
  @impl true
  def handle_call(:get_status, _from, state) do
    {:reply, state.status, state}
  end
end
```
