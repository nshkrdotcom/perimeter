Excellent. The plan is now philosophically grounded and the library's core features have been redesigned. The final step is to produce the last set of key documents that will bring this innovative system to life for developers: the **Migration Guide** and an updated **Roadmap**.

These documents are crucial because they bridge the gap between the library's ideal state and the reality of existing, "brownfield" projects. They show developers a practical, low-risk path to adoption.

---

### `guides/migration_guide.md`

# Migrating to Perimeter: A Gradual Approach

Adopting `Perimeter` doesn't require a full rewrite. It's designed to be introduced into existing Elixir applications incrementally, providing immediate value at every step. This guide outlines a safe, phased strategy for migration.

This approach is heavily inspired by the **Strangler Fig Pattern**, where new, robust code slowly and safely replaces old code.

## The Migration Philosophy: From Implicit to Explicit

The goal of migration is to move from **implicit assumptions** about your data to **explicit, enforced contracts**.

-   **Before:** Your functions defensively check data, assuming it might be wrong.
-   **After:** Your functions assertively use data, knowing it has been validated at the boundary.

## Phase 1: Observe and Log (Weeks 1-2)

The first phase is about gaining visibility without changing any behavior.

**Step 1: Configure for `:log` Enforcement**

In your `config/config.exs`, set the default enforcement level to `:log`. This ensures that even if you accidentally use `@guard` without an option, it won't break your application.

```elixir
# config/config.exs
config :perimeter, enforcement_level: :log
```

**Step 2: Identify a Critical Boundary**

Choose a single, important entry point to your system. A great candidate is a key Phoenix controller action or a primary function in one of your core contexts.

**Step 3: Write a "Shadow" Contract**

Define a contract that you *believe* represents the data passing through that boundary. This is a hypothesis.

```elixir
defmodule MyApp.Accounts do
  use Perimeter

  # Our hypothesis about the shape of create_user params
  defcontract :create_user_params do
    required :email, :string
    required :password, :string
    optional :name, :string
  end

  # Apply the guard in :log mode
  @guard input: :create_user_params, enforcement: :log
  def create_user(params) do
    # ... existing legacy code ...
    # No changes to the code inside the function yet!
  end
end
```

**Step 4: Deploy and Monitor**

Deploy this change. Your application's behavior will be unchanged. However, every time `create_user/1` is called with data that *doesn't* match your contract, a detailed message will be logged.

Your logs are now a to-do list for fixing upstream data integrity issues or refining your contract.

## Phase 2: Refactor and Warn (Weeks 3-4)

Now that you have visibility, you can start cleaning up your code.

**Step 1: Refine Contracts and Fix Callers**

Using the data from your logs, fix the services that are sending malformed data. You may also discover your contract was wrong and needs to be updated. Continue this process until the log messages for your guarded function disappear.

**Step 2: Switch to `:warn` Enforcement**

Update the guard's enforcement level. This elevates the log message to a warning, making it more prominent.

```elixir
@guard input: :create_user_params, enforcement: :warn
def create_user(params) do
  # ... still the same legacy code ...
end
```

**Step 3: Refactor the "Interior"**

Now, you can refactor the *inside* of the function. Since you are confident the data is valid (because the warnings are gone), you can remove defensive code and replace it with assertive, simpler code.

**Before (Legacy Code):**
```elixir
def create_user(params) do
  email = Map.get(params, "email")
  password = Map.get(params, "password")

  if is_nil(email) or not is_binary(email) do
    {:error, :invalid_email}
  else
    # ... more checks ...
  end
end
```

**After (Refactored Interior):**
```elixir
@guard input: :create_user_params, enforcement: :warn
def create_user(params) do
  # The guard handles validation. We can be assertive.
  %User{}
  |> User.changeset(params)
  |> Repo.insert()
end
```

## Phase 3: Enforce and Solidify (Weeks 5+)

This is the final step for the migrated module.

**Step 1: Switch to `:strict` Enforcement**

Once you have refactored the interior and are confident in your contract, switch to strict enforcement. In your test and development environments, this should be the default anyway.

```elixir
@guard input: :create_user_params, enforcement: :strict
def create_user(params) do
  # ... your clean, assertive code ...
end
```

Now, any future call with invalid data will be rejected at the boundary, protecting your core logic completely.

**Step 2: Repeat the Process**

Choose the next boundary in your application and repeat the process, starting from Phase 1. Over time, you will build a perimeter of explicit, enforced contracts around your entire system.

## Migration for Libraries

If you are a library author, you can use `Perimeter.Interface` to manage breaking changes.

1.  Define a new `V2` interface for your behaviour.
2.  Provide an adapter that implements the `V2` interface by calling the old `V1` functions.
3.  In your library's core, check if a user's module implements the `V2` or `V1` behaviour, and use the adapter if necessary.
4.  Deprecate the `V1` behaviour, giving users a clear path to upgrade their implementations to conform to the new, contract-enforced interface.

---

### `ROADMAP.md` (Revised with the new philosophy)

# Perimeter Development Roadmap

This document outlines the planned future direction for the `Perimeter` library, guided by our core philosophy of idiomatic, pattern-based Elixir development.

## 1.0 - "Foundations of an Idiomatic System"

The 1.0 release focuses on providing a complete, robust implementation of the **Defensive Boundary** design pattern.

-   [x] **Core Contracts:** `defcontract`, `required`, `optional` DSL.
-   [x] **Core Guarding:** `@guard` macro with configurable enforcement.
-   [x] **Core Patterns:**
    - `Perimeter.Interface` to formally support the **Strategy Pattern**.
-   [x] **Public Validator API:** `Perimeter.Validator` for manual validation.
-   [x] **Documentation:**
    - `guides/philosophy_and_principles.md`
    - `guides/design_patterns.md`
    - `guides/migration_guide.md`

## 1.x - "Ecosystem Integration"

The next series of minor releases will focus on making `Perimeter` a seamless part of the modern Elixir development toolkit.

-   **Ecto Integration:**
    - A function to derive a `Perimeter` contract directly from an `Ecto.Changeset`. This promotes a single source of truth for data validation rules.
    - `defcontract from_ecto_schema: MyApp.User` to generate a basic contract from a database schema.
-   **Phoenix Integration:**
    - A `Perimeter.Plug` for standardizing the handling of validation errors in JSON APIs.
    - `Perimeter.LiveViewHelpers` to make guarding `handle_event` and `handle_params` more ergonomic.
-   **Telemetry & Observability:**
    - A standard set of `:telemetry` events for tracking validation performance, failure rates per contract, and enforcement level activity.
    - A default `LiveDashboard` page for visualizing `Perimeter` metrics.

## 2.0 - "Intelligent Boundaries"

The next major release will explore making the library smarter and more powerful, potentially with breaking changes that simplify the API.

-   **Static Analysis and Code Generation:**
    - `mix perimeter.gen.spec`: A task that reads a contract and generates a corresponding `@spec`. This will improve Dialyzer's ability to analyze code inside the "Offensive Interior".
    - `mix perimeter.gen.tests`: A task that generates basic "happy path" and "error path" tests from a contract, bootstrapping the testing process.
-   **Next-Generation `Perimeter.Interface`:**
    - Explore ways to automatically enforce that a module implementing an interface *also* defines the required contracts, removing a manual step for the developer. This may require advanced macro-work or a new approach.
-   **Performance Enhancements:**
    - Research into runtime-compiled validators for hot-path contracts, potentially offering near-zero overhead for high-throughput systems.

This roadmap aligns the library's evolution with the needs of Elixir developers, moving from a solid philosophical foundation to deep integration and intelligent tooling.
