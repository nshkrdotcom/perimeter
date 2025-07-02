Excellent. We've established the philosophy, redesigned the library, created the core guides, and defined the project's future. The final, crucial step is to produce the documentation that makes the library truly "innovative for greenfield Elixir development": a guide on how to architect a new application from scratch using `Perimeter`'s principles.

This document will be the capstone, tying everything together and showing developers the "happy path" from day one.

---

### `guides/greenfield_architecture.md`

# Architecting a New Elixir Application with Perimeter

This guide presents an architectural blueprint for building new, "greenfield" Elixir applications using `Perimeter` from the very beginning. By adopting these patterns, you can create a system that is robust, maintainable, and idiomatic from day one.

The architecture is built around two core concepts: **Phoenix as the Web Boundary** and **Contexts as the Domain Boundary**.

## The Core Architecture

A `Perimeter`-driven application consists of three primary layers:

```
+-------------------------------------------------------------------+
|                           1. The Web Layer                        |
|        (Phoenix: Controllers, LiveViews, Channels, Plugs)         |
|                                                                   |
|   <-- Perimeter Guards at this Boundary (Validates raw input) --> |
+-------------------------------------------------------------------+
|                         2. The Domain Layer                       |
|           (Core Contexts: Accounts, Sales, Shipping)              |
|                                                                   |
|  <-- Perimeter Guards at this Boundary (Ensures domain integrity) |
+-------------------------------------------------------------------+
|                         3. The Data Layer                         |
|                       (Ecto Schemas and Repos)                    |
+-------------------------------------------------------------------+
```

-   **The Web Layer** is responsible for handling external interactions (HTTP requests, WebSocket events). Its only job is to translate these interactions into calls to the Domain Layer.
-   **The Domain Layer** contains your business logic. It knows nothing about the web. Its functions operate on pure Elixir data structures.
-   **The Data Layer** is responsible for persistence, using Ecto to interact with the database.

**`Perimeter` is the gatekeeper between these layers.**

## Step-by-Step Greenfield Blueprint

### Step 1: Define Your Domain with Ecto and Contracts

Before writing a single line of web code, define your core data structures. For each core entity (e.g., `User`, `Order`), create three modules:

1.  **The Ecto Schema:** `lib/my_app/accounts/user.ex`
2.  **The Context:** `lib/my_app/accounts.ex`
3.  **The Contracts:** `lib/my_app/accounts/contracts.ex` (A new, dedicated module for contracts)

```elixir
# lib/my_app/accounts/user.ex
defmodule MyApp.Accounts.User do
  use Ecto.Schema
  # ... Ecto schema definition ...
end

# lib/my_app/accounts/contracts.ex
defmodule MyApp.Accounts.Contracts do
  use Perimeter.Contract
  alias MyApp.Accounts.User

  # A contract for creating a user. Notice it has no `id`.
  defcontract :create_user_params do
    required :email, :string, format: ~r/@/
    required :password, :string, min_length: 12
  end

  # A contract for the data returned by the context.
  defcontract :user_output do
    required :id, :string
    required :email, :string
    required :__struct__, :atom, in: [User]
  end
end

# lib/my_app/accounts.ex
defmodule MyApp.Accounts do
  alias MyApp.Accounts.Contracts
  alias MyApp.Repo

  # Guard the public function of your context.
  # This is the INNER boundary. It protects your domain logic.
  @guard input: Contracts.create_user_params, output: Contracts.user_output
  def create_user(params) do
    # Inside here, `params` are guaranteed to be valid.
    # The return value will be checked against the `:user_output` contract.
    with {:ok, %User{} = user} <- # ... Ecto logic ... do
      {:ok, user}
    end
  end
end
```
By defining contracts alongside your context, you create a self-documenting, testable, and robust domain layer *before* any web code exists.

### Step 2: Build the Web Boundary with Phoenix

Now, build the web interface that interacts with your domain.

```elixir
# lib/my_app_web/controllers/user_controller.ex
defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller
  alias MyApp.Accounts
  alias MyApp.Accounts.Contracts

  # Action plugs are a great way to handle parameter loading and validation.
  plug :validate_params, [action: :create, contract: Contracts.create_user_params] when action in [:create]

  def create(conn, validated_params) do
    # The `validated_params` have already been checked by the plug.
    # This is the OUTER boundary. It protects your web layer from bad HTTP requests.
    case Accounts.create_user(validated_params) do
      {:ok, user} ->
        conn
        |> put_status(:created)
        |> render("show.json", user: user)

      {:error, _changeset} = error ->
        # The context function returned an error. Pass it up.
        {:error, error}
    end
  end

  # A reusable validation plug.
  defp validate_params(conn, opts) do
    contract = Keyword.fetch!(opts, :contract)
    with {:ok, validated_params} <- Perimeter.Validator.validate(contract, :input, conn.params) do
      # If valid, assign the params for the controller action to use.
      assign(conn, :validated_params, validated_params)
    else
      {:error, error} ->
        # If invalid, halt the plug pipeline and send a 422 response.
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(json: MyAppWeb.ErrorJSON)
        |> render("422.json", error: error)
        |> halt()
    end
  end
end
```
This two-layer guard system is incredibly robust:
1.  The **Outer Guard** (in the plug) protects your web layer from malformed JSON/params and provides immediate, clear API error messages.
2.  The **Inner Guard** (in the context) protects your domain logic, ensuring that no other part of the Elixir application (e.g., a background job, another context) can call it with invalid data.

### Step 3: Implement Pluggable Strategies with `Perimeter.Interface`

For parts of your system that require interchangeable components (e.g., payment gateways, notification services), use `Perimeter.Interface` to define the "pluggable strategy" pattern.

**1. Define the Interface:**

```elixir
# lib/my_app/notifications/notifier.ex
defmodule MyApp.Notifications.Notifier do
  use Perimeter.Interface # This defines a behaviour and contract template

  @doc "Sends a notification."
  @callback send(recipient :: any(), message :: String.t(), opts :: map()) :: :ok | {:error, term()}

  # All implementations MUST define an `:opts` contract.
  defcontract :opts do
    # Base implementations can define shared options here.
    optional :trace_id, :string
  end
end
```

**2. Create Implementations:**

```elixir
# lib/my_app/notifications/email_notifier.ex
defmodule MyApp.Notifications.EmailNotifier do
  @behaviour MyApp.Notifications.Notifier # Implement the behaviour
  use Perimeter.Contract                  # To define this module's contract

  # Define the specific options for this strategy
  defcontract :opts do
    compose MyApp.Notifications.Notifier.opts() # Compose shared options
    required :subject, :string
  end

  @impl true
  @guard input: :opts # Guard the implementation with its specific contract
  def send(recipient, message, opts) do
    # ... logic to send an email using the validated opts ...
  end
end
```

**3. Use the Strategy in Your Domain:**

```elixir
# lib/my_app/accounts.ex
defmodule MyApp.Accounts do
  # ...

  def notify_user(user, message) do
    # Get the configured notifier (e.g., from Application config)
    notifier = Application.get_env(:my_app, :notifier_impl)
    opts = # ... construct opts for the specific notifier ...

    # The call is polymorphic. The correct implementation will be called,
    # and its own guard will validate its specific opts.
    notifier.send(user.email, message, opts)
  end
end
```
This architecture creates a system that is:
-   **Decoupled:** The web layer doesn't know how the domain works, and the domain doesn't know how notifications are sent.
-   **Explicit:** Contracts at every boundary make data flow obvious.
-   **Testable:** Each layer can be tested in isolation. You can test the domain context without needing a simulated web request. You can test a notifier strategy without needing a full user object.
-   **Resilient:** Invalid data is stopped at the earliest possible moment, protecting your core logic.

This greenfield blueprint is the culmination of the `Perimeter` philosophy. It moves beyond just "validating data" to providing a comprehensive pattern language for building truly robust, modern Elixir applications.