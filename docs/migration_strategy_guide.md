# Migration Strategy Guide: From Traditional Elixir to Type-Safe Boundaries

## Overview

This guide provides a comprehensive strategy for migrating existing Elixir applications to use the "Defensive Boundary / Offensive Interior" pattern. The migration is designed to be gradual, allowing teams to adopt type contracts incrementally while maintaining system stability.

## Migration Phases

### Phase 0: Assessment and Planning

Before beginning migration, assess your current codebase:

```elixir
defmodule MigrationAssessment do
  @moduledoc """
  Tools to assess codebase readiness for type contract migration.
  """
  
  def analyze_project(app_name) do
    modules = get_all_modules(app_name)
    
    %{
      total_modules: length(modules),
      actions: count_pattern(modules, &uses?(&1, Jido.Action)),
      agents: count_pattern(modules, &uses?(&1, Jido.Agent)),
      genservers: count_pattern(modules, &uses?(&1, GenServer)),
      phoenix_controllers: count_pattern(modules, &uses?(&1, Phoenix.Controller)),
      boundary_candidates: identify_boundary_modules(modules),
      antipattern_risks: scan_for_antipatterns(modules)
    }
  end
  
  defp identify_boundary_modules(modules) do
    modules
    |> Enum.filter(&is_boundary_module?/1)
    |> Enum.map(&module_info/1)
  end
  
  defp is_boundary_module?(module) do
    # Modules that interact with external systems
    exports = module.__info__(:functions)
    
    Enum.any?(exports, fn {name, _arity} ->
      name in [:run, :call, :handle_call, :create, :update, :delete]
    end)
  end
end
```

### Phase 1: Infrastructure Setup

#### Step 1: Add Dependencies

```elixir
# mix.exs
defp deps do
  [
    # Existing deps...
    {:jido_type_enforcement, "~> 1.0"},
    {:jido_boundary_guard, "~> 1.0"},
    
    # Development tools
    {:boundary, "~> 0.10", runtime: false},
    {:credo_type_check, "~> 1.0", only: [:dev, :test]}
  ]
end
```

#### Step 2: Configure Type Enforcement

```elixir
# config/config.exs
config :jido_type_enforcement,
  default_level: :log,  # Start with logging only
  telemetry_enabled: true,
  cache_size: 1000

# config/dev.exs  
config :jido_type_enforcement,
  default_level: :warn  # Stricter in development

# config/test.exs
config :jido_type_enforcement,
  default_level: :strict  # Strict in tests
```

#### Step 3: Create Migration Helpers

```elixir
defmodule MyApp.TypeMigration do
  @moduledoc """
  Helpers for gradual type contract migration.
  """
  
  defmacro __using__(opts) do
    level = Keyword.get(opts, :level, :log)
    
    quote do
      use Jido.BoundaryGuard, enforcement: unquote(level)
      use Jido.TypeContract
      
      # Migration helper to wrap existing functions
      defmacro migrate_function(name, arity, contract) do
        quote do
          original = :"__original_#{unquote(name)}"
          
          # Rename original function
          defdelegate unquote(original)(var!(args)), to: __MODULE__, as: unquote(name)
          
          # Create wrapper with validation
          def unquote(name)(args) do
            case validate_contract(unquote(contract), args) do
              {:ok, validated} ->
                apply(__MODULE__, unquote(original), [validated])
              {:error, violations} ->
                MyApp.TypeMigration.handle_violation(violations, unquote(level))
                apply(__MODULE__, unquote(original), [args])
            end
          end
        end
      end
    end
  end
end
```

### Phase 2: Identify and Migrate Boundaries

#### Step 1: Start with External Interfaces

Priority order for migration:

1. **HTTP/API Controllers**
```elixir
defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller
  use MyApp.TypeMigration, level: :log
  
  # Before: No validation
  def create(conn, params) do
    case Users.create_user(params["user"]) do
      {:ok, user} -> json(conn, user)
      {:error, _} -> send_resp(conn, 422, "Error")
    end
  end
  
  # After: With contract
  defcontract :create_params do
    required :user, :map do
      required :email, :string
      required :password, :string
      optional :name, :string
    end
  end
  
  @guard function: :create, input: :create_params
  def create(conn, params) do
    # Same implementation, but params are validated
    case Users.create_user(params.user) do
      {:ok, user} -> json(conn, user)
      {:error, _} -> send_resp(conn, 422, "Error")
    end
  end
end
```

2. **GenServer Interfaces**
```elixir
defmodule MyApp.DataProcessor do
  use GenServer
  use MyApp.TypeMigration, level: :warn
  
  defcontract :process_request do
    required :type, :atom, in: [:sync, :async]
    required :data, :map
    optional :options, :keyword_list
  end
  
  # Migrate handle_call
  def handle_call({:process, request}, from, state) do
    case validate_contract(:process_request, request) do
      {:ok, valid_request} ->
        do_process(valid_request, from, state)
      {:error, violations} ->
        {:reply, {:error, format_violations(violations)}, state}
    end
  end
end
```

#### Step 2: Migrate Internal Boundaries

Focus on module boundaries that cross contexts:

```elixir
defmodule MyApp.Accounts do
  use MyApp.TypeMigration
  
  # Define contracts for context boundaries
  defcontract :create_user_attrs do
    required :email, :string
    required :password, :string
    optional :profile, :map do
      optional :name, :string
      optional :bio, :string
    end
  end
  
  # Original function
  def create_user(attrs) do
    # Existing implementation
  end
  
  # Add validated version alongside
  @guard function: :create_user_validated, input: :create_user_attrs
  def create_user_validated(attrs) do
    create_user(attrs)  # Delegates to original
  end
  
  # Gradually update callers to use validated version
end
```

### Phase 3: Address Antipatterns

#### Fix Non-Assertive Map Access

```elixir
defmodule AntipatternFixes do
  # Before: Non-assertive access
  def process_user(user) do
    name = user[:name] || "Unknown"
    email = user[:email]
    age = user[:age]
    
    # Process with possibly nil values
  end
  
  # After: Contract-enforced structure
  defcontract :user do
    required :email, :string
    optional :name, :string, default: "Unknown"
    optional :age, :integer
  end
  
  @guard input: :user
  def process_user(user) do
    # Assertive access - we know email exists
    %{email: email, name: name} = user
    age = user[:age]  # Still optional
    
    # Process with guaranteed structure
  end
end
```

#### Fix Dynamic Atom Creation

```elixir
defmodule AtomSafetyMigration do
  # Before: Dangerous dynamic atom creation
  def process_status(status_string) do
    String.to_atom(status_string)
  end
  
  # After: Safe with explicit mapping
  defcontract :status_update do
    required :status, :string, in: ~w(active inactive pending banned)
  end
  
  @guard input: :status_update
  def process_status(%{status: status_string}) do
    # Safe mapping to existing atoms
    case status_string do
      "active" -> :active
      "inactive" -> :inactive
      "pending" -> :pending
      "banned" -> :banned
    end
  end
end
```

### Phase 4: Incremental Enforcement

#### Step 1: Monitor and Measure

```elixir
defmodule MigrationMonitor do
  use GenServer
  
  def init(_) do
    :telemetry.attach(
      "migration-monitor",
      [:jido, :boundary, :violation],
      &handle_violation/4,
      nil
    )
    
    {:ok, %{violations: %{}, start_time: System.monotonic_time()}}
  end
  
  def handle_violation(_event, measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:violation, metadata.module, metadata.violation})
  end
  
  def report do
    GenServer.call(__MODULE__, :report)
  end
  
  def handle_call(:report, _from, state) do
    report = %{
      total_violations: count_violations(state.violations),
      by_module: top_violators(state.violations),
      by_type: violation_types(state.violations),
      uptime: System.monotonic_time() - state.start_time
    }
    
    {:reply, report, state}
  end
end
```

#### Step 2: Gradual Enforcement Increase

```elixir
defmodule EnforcementScheduler do
  @moduledoc """
  Gradually increases enforcement levels based on violation metrics.
  """
  
  def schedule_enforcement_increase(app) do
    # Week 1-2: Log only
    set_all_modules_enforcement(app, :log)
    
    # Week 3-4: Warn on violations
    :timer.apply_after(:timer.weeks(2), __MODULE__, :increase_enforcement, [app, :warn])
    
    # Week 5-6: Strict for specific modules
    :timer.apply_after(:timer.weeks(4), __MODULE__, :selective_strict, [app])
    
    # Week 7+: Full strict mode
    :timer.apply_after(:timer.weeks(6), __MODULE__, :increase_enforcement, [app, :strict])
  end
  
  def selective_strict(app) do
    # Start with least critical modules
    safe_modules = identify_safe_modules(app)
    
    Enum.each(safe_modules, fn module ->
      Jido.TypeEnforcement.set_module_level(module, :strict)
    end)
  end
end
```

### Phase 5: Team Migration Patterns

#### Pattern 1: The Strangler Fig

Wrap old implementations with new contract-based interfaces:

```elixir
defmodule LegacyWrapper do
  use Jido.TypeContract
  
  # Old module we're replacing
  alias MyApp.LegacyUserService
  
  defcontract :user_input do
    required :username, :string
    required :email, :string
    optional :metadata, :map
  end
  
  # New interface with contracts
  @guard input: :user_input
  def create_user(params) do
    # Transform to legacy format
    legacy_params = %{
      "user_name" => params.username,
      "user_email" => params.email,
      "extra" => params[:metadata] || %{}
    }
    
    # Call legacy service
    case LegacyUserService.create(legacy_params) do
      {:ok, user} -> {:ok, transform_legacy_user(user)}
      error -> error
    end
  end
  
  # Gradually move logic from legacy to new module
end
```

#### Pattern 2: The Branch by Abstraction

Create abstraction layer for gradual migration:

```elixir
defmodule AbstractionLayer do
  @callback validate_input(map()) :: {:ok, map()} | {:error, term()}
  @callback process(map()) :: {:ok, term()} | {:error, term()}
  
  defmodule LegacyImpl do
    @behaviour AbstractionLayer
    
    def validate_input(input), do: {:ok, input}  # No validation
    def process(input), do: MyApp.LegacyProcessor.run(input)
  end
  
  defmodule ContractImpl do
    @behaviour AbstractionLayer
    use Jido.TypeContract
    
    defcontract :input do
      required :data, :map
      required :format, :atom
    end
    
    def validate_input(input) do
      validate_contract(:input, input)
    end
    
    def process(input) do
      # New implementation
    end
  end
  
  # Switch implementations via config
  def impl do
    Application.get_env(:my_app, :processor_impl, LegacyImpl)
  end
end
```

### Phase 6: Tooling and Automation

#### Custom Mix Tasks

```elixir
defmodule Mix.Tasks.TypeMigration.Status do
  use Mix.Task
  
  @shortdoc "Shows type migration status"
  
  def run(_args) do
    Mix.Task.run("compile")
    
    report = analyze_migration_status()
    
    Mix.shell().info("""
    Type Migration Status
    ====================
    
    Total Modules: #{report.total_modules}
    Migrated: #{report.migrated_count} (#{report.migrated_percentage}%)
    In Progress: #{report.in_progress_count}
    Not Started: #{report.not_started_count}
    
    Enforcement Levels:
    - Strict: #{report.strict_count}
    - Warn: #{report.warn_count}
    - Log: #{report.log_count}
    
    Recent Violations: #{report.recent_violations}
    
    Next Steps:
    #{format_next_steps(report)}
    """)
  end
end
```

#### CI/CD Integration

```yaml
# .github/workflows/type-safety.yml
name: Type Safety Checks

on: [push, pull_request]

jobs:
  type-checks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Run type contract tests
        run: |
          mix test --only contract_test
          
      - name: Check migration progress
        run: |
          mix type_migration.status --format json > migration-status.json
          
      - name: Validate no new violations
        run: |
          mix type_migration.check --baseline .type-baseline.json
          
      - name: Generate coverage report
        run: |
          mix type_migration.coverage --min 80
```

### Migration Timeline Example

```elixir
defmodule MigrationTimeline do
  @timeline [
    {0, "Setup infrastructure, add dependencies"},
    {1, "Migrate external APIs (controllers, webhooks)"},
    {2, "Migrate GenServers and process boundaries"},
    {3, "Fix non-assertive patterns in critical paths"},
    {4, "Migrate internal module boundaries"},
    {5, "Address remaining antipatterns"},
    {6, "Increase enforcement to :warn"},
    {8, "Selective :strict enforcement"},
    {10, "Full :strict mode in production"},
    {12, "Remove migration helpers"}
  ]
  
  def weeks_to_complete(module_count) do
    base_weeks = 12
    scaling_factor = module_count / 100
    
    base_weeks + (scaling_factor * 2)
  end
end
```

## Post-Migration Best Practices

### 1. Maintain Type Contracts

```elixir
defmodule ContractMaintenance do
  # Regular contract review
  def review_contracts do
    all_contracts()
    |> Enum.filter(&contract_unused?/1)
    |> Enum.each(&log_unused_contract/1)
  end
  
  # Contract versioning for API evolution
  defcontract :api_v1 do
    required :data, :map
  end
  
  defcontract :api_v2 do
    required :data, :map
    required :version, :integer
    optional :metadata, :map
  end
end
```

### 2. Performance Monitoring

```elixir
defmodule PerformanceMonitor do
  def setup do
    :telemetry.attach_many(
      "type-performance",
      [
        [:jido, :type, :validation, :start],
        [:jido, :type, :validation, :stop]
      ],
      &handle_event/4,
      nil
    )
  end
  
  def handle_event([:jido, :type, :validation, :stop], measurements, metadata, _) do
    duration = measurements.duration
    
    if duration > :timer.milliseconds(10) do
      Logger.warning("Slow validation: #{metadata.contract} took #{duration}μs")
    end
  end
end
```

## Conclusion

Successful migration to type-safe boundaries requires:

1. **Gradual Approach**: Start with logging, increase enforcement over time
2. **Team Buy-in**: Education and clear benefits demonstration
3. **Tool Support**: Automation and monitoring
4. **Clear Patterns**: Consistent approaches to common scenarios
5. **Measurement**: Track progress and adjust strategy

The migration process typically takes 3-6 months for medium-sized applications, but results in:
- Fewer runtime errors
- Better documentation through contracts
- Easier onboarding for new developers
- More confident refactoring
- Clear system boundaries