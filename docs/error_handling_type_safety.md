# Error Handling and Type Safety Guide

## Overview

This guide demonstrates how to implement robust error handling within the "Defensive Boundary / Offensive Interior" pattern. It shows how type-safe error handling can prevent common antipatterns while providing clear, actionable error information.

## Core Principles of Type-Safe Error Handling

### 1. Errors as First-Class Types

Instead of generic error tuples, use structured error types:

```elixir
defmodule Jido.Error do
  @moduledoc """
  Structured error representation with type safety guarantees.
  """
  
  use Jido.TypeContract
  
  @type t :: %__MODULE__{
    type: error_type(),
    message: String.t(),
    details: map(),
    stacktrace: list(),
    context: map()
  }
  
  @type error_type ::
    :validation_error |
    :execution_error |
    :timeout |
    :authorization_error |
    :not_found |
    :conflict |
    :system_error
  
  defstruct [:type, :message, :details, :stacktrace, :context]
  
  # Contract for error creation
  defcontract :error_params do
    required :type, :atom, in: [
      :validation_error, :execution_error, :timeout,
      :authorization_error, :not_found, :conflict, :system_error
    ]
    required :message, :string
    optional :details, :map
    optional :context, :map
  end
  
  @guard input: :error_params
  def new(params) do
    %__MODULE__{
      type: params.type,
      message: params.message,
      details: params[:details] || %{},
      stacktrace: get_clean_stacktrace(),
      context: params[:context] || %{}
    }
  end
  
  # Specific error constructors
  def validation_error(message, violations) when is_list(violations) do
    new(%{
      type: :validation_error,
      message: message,
      details: %{violations: format_violations(violations)}
    })
  end
  
  def not_found(resource_type, identifier) do
    new(%{
      type: :not_found,
      message: "#{resource_type} not found",
      details: %{resource_type: resource_type, identifier: identifier}
    })
  end
end
```

### 2. Error Boundaries with Pattern Matching

Avoid complex `else` clauses by using specific error handling:

```elixir
defmodule ErrorBoundaryPatterns do
  use Jido.TypeContract
  
  # Instead of complex with/else
  def process_with_boundaries(params) do
    # Each boundary returns typed errors
    with {:ok, validated} <- validate_input(params),
         {:ok, authorized} <- check_authorization(validated),
         {:ok, result} <- execute_action(authorized) do
      {:ok, format_result(result)}
    end
  end
  
  # Boundary functions return specific error types
  defp validate_input(params) do
    case validate_contract(:input, params) do
      {:ok, valid} -> 
        {:ok, valid}
      {:error, violations} ->
        {:error, Jido.Error.validation_error("Invalid input", violations)}
    end
  end
  
  defp check_authorization(params) do
    if authorized?(params) do
      {:ok, params}
    else
      {:error, Jido.Error.authorization_error(
        "Insufficient permissions",
        %{required_role: :admin, current_role: params[:role]}
      )}
    end
  end
  
  defp execute_action(params) do
    try do
      result = do_execute(params)
      {:ok, result}
    rescue
      e in RuntimeError ->
        {:error, Jido.Error.execution_error(
          "Action execution failed",
          %{original_error: Exception.message(e)}
        )}
    end
  end
end
```

### 3. Typed Error Propagation

Ensure errors maintain their type information through the system:

```elixir
defmodule TypedErrorPropagation do
  use Jido.TypeContract
  
  # Define error result contract
  defcontract :action_result do
    one_of [
      {:ok, :map},
      {:error, Jido.Error}
    ]
  end
  
  # Actions return typed results
  defmodule CreateUserAction do
    use Jido.Action
    
    @impl true
    @guard output: :action_result
    def run(params, context) do
      with {:ok, user} <- create_user(params),
           {:ok, _} <- send_welcome_email(user) do
        {:ok, %{user: user}}
      else
        {:error, %Jido.Error{} = error} ->
          # Propagate typed error
          {:error, enrich_error(error, params)}
        {:error, other} ->
          # Convert untyped errors
          {:error, Jido.Error.system_error(
            "Unexpected error",
            %{original: other}
          )}
      end
    end
    
    defp enrich_error(error, params) do
      %{error | 
        context: Map.merge(error.context, %{
          action: __MODULE__,
          params: sanitize_params(params)
        })
      }
    end
  end
end
```

## Error Handling Patterns

### Pattern 1: Validation Error Aggregation

Collect all validation errors instead of failing on first:

```elixir
defmodule ValidationAggregation do
  use Jido.TypeContract
  
  def validate_comprehensive(data) do
    validators = [
      &validate_required_fields/1,
      &validate_field_types/1,
      &validate_business_rules/1,
      &validate_relationships/1
    ]
    
    # Run all validators, collecting errors
    results = Enum.map(validators, fn validator ->
      case validator.(data) do
        :ok -> {:ok, []}
        {:error, violations} -> {:error, violations}
      end
    end)
    
    # Aggregate results
    case aggregate_validation_results(results) do
      [] -> 
        {:ok, data}
      violations ->
        {:error, Jido.Error.validation_error(
          "Validation failed",
          violations
        )}
    end
  end
  
  defp aggregate_validation_results(results) do
    results
    |> Enum.flat_map(fn
      {:ok, _} -> []
      {:error, violations} -> violations
    end)
    |> Enum.uniq_by(& &1.field)  # Deduplicate by field
  end
  
  defp validate_required_fields(data) do
    required = [:name, :email, :age]
    missing = required -- Map.keys(data)
    
    case missing do
      [] -> :ok
      fields ->
        violations = Enum.map(fields, fn field ->
          %{field: field, error: "is required"}
        end)
        {:error, violations}
    end
  end
end
```

### Pattern 2: Error Recovery and Compensation

Implement recovery strategies at boundaries:

```elixir
defmodule ErrorRecovery do
  use Jido.TypeContract
  
  defmodule RecoverableAction do
    use Jido.Action
    
    defcontract :recovery_strategy do
      required :type, :atom, in: [:retry, :compensate, :fallback, :fail]
      optional :max_retries, :integer, default: 3
      optional :backoff_ms, :integer, default: 1000
      optional :fallback_value, :any
    end
    
    @impl true
    def run(params, context) do
      strategy = context[:recovery_strategy] || %{type: :fail}
      
      execute_with_recovery(params, context, strategy)
    end
    
    defp execute_with_recovery(params, context, %{type: :retry} = strategy) do
      max_retries = strategy[:max_retries] || 3
      backoff = strategy[:backoff_ms] || 1000
      
      retry_with_backoff(
        fn -> do_execute(params, context) end,
        max_retries,
        backoff
      )
    end
    
    defp execute_with_recovery(params, context, %{type: :compensate}) do
      case do_execute(params, context) do
        {:ok, result} ->
          {:ok, result}
        {:error, error} ->
          case compensate(params, context, error) do
            {:ok, compensated} ->
              {:ok, compensated}
            {:error, comp_error} ->
              {:error, Jido.Error.execution_error(
                "Failed to execute and compensate",
                %{
                  original_error: error,
                  compensation_error: comp_error
                }
              )}
          end
      end
    end
    
    defp retry_with_backoff(fun, retries, backoff, attempt \\ 1) do
      case fun.() do
        {:ok, _} = result ->
          result
        {:error, error} when attempt < retries ->
          Process.sleep(backoff * attempt)
          retry_with_backoff(fun, retries, backoff, attempt + 1)
        {:error, error} ->
          {:error, enrich_with_retry_info(error, attempt)}
      end
    end
  end
end
```

### Pattern 3: Error Context Enrichment

Add context to errors as they propagate through boundaries:

```elixir
defmodule ErrorContextEnrichment do
  use Jido.TypeContract
  
  defmodule ContextualError do
    @moduledoc """
    Enriches errors with contextual information at each boundary.
    """
    
    def with_context(error_or_result, context) do
      case error_or_result do
        {:error, %Jido.Error{} = error} ->
          {:error, add_context(error, context)}
        {:error, other} ->
          {:error, wrap_with_context(other, context)}
        result ->
          result
      end
    end
    
    defp add_context(%Jido.Error{} = error, context) do
      %{error |
        context: Map.merge(error.context, context),
        stacktrace: maybe_add_boundary_frame(error.stacktrace)
      }
    end
    
    defp wrap_with_context(error, context) do
      Jido.Error.new(%{
        type: :system_error,
        message: "Wrapped error at boundary",
        details: %{original_error: error},
        context: context
      })
    end
    
    def with_telemetry(error_or_result, event_name) do
      case error_or_result do
        {:error, error} ->
          :telemetry.execute(
            [:jido, :error, event_name],
            %{count: 1},
            %{error: error}
          )
          {:error, error}
        result ->
          result
      end
    end
  end
  
  # Usage in boundaries
  def process_order(order_params) do
    order_params
    |> validate_order()
    |> ContextualError.with_context(%{boundary: :order_validation})
    |> calculate_pricing()
    |> ContextualError.with_context(%{boundary: :pricing})
    |> check_inventory()
    |> ContextualError.with_context(%{boundary: :inventory})
    |> ContextualError.with_telemetry(:order_processing)
  end
end
```

### Pattern 4: Type-Safe Error Transformation

Transform errors between different boundary types:

```elixir
defmodule ErrorTransformation do
  @moduledoc """
  Transforms internal errors to appropriate external representations.
  """
  
  # Transform internal errors to HTTP responses
  def to_http_response({:error, %Jido.Error{} = error}) do
    %{
      status: error_to_status(error.type),
      body: %{
        error: %{
          type: error.type,
          message: error.message,
          details: sanitize_details(error.details)
        }
      }
    }
  end
  
  def to_http_response({:ok, result}) do
    %{status: 200, body: result}
  end
  
  defp error_to_status(type) do
    case type do
      :validation_error -> 422
      :authorization_error -> 403
      :not_found -> 404
      :conflict -> 409
      :timeout -> 408
      _ -> 500
    end
  end
  
  # Transform to GraphQL errors
  def to_graphql_error({:error, %Jido.Error{} = error}) do
    %{
      message: error.message,
      extensions: %{
        code: error.type |> Atom.to_string() |> String.upcase(),
        details: error.details
      },
      path: error.context[:graphql_path]
    }
  end
  
  # Transform to user-friendly messages
  def to_user_message({:error, %Jido.Error{} = error}) do
    case error.type do
      :validation_error ->
        format_validation_message(error.details.violations)
      :authorization_error ->
        "You don't have permission to perform this action."
      :not_found ->
        "The requested #{error.details.resource_type} could not be found."
      _ ->
        "An error occurred. Please try again later."
    end
  end
end
```

## Advanced Error Handling Patterns

### Circuit Breaker Pattern

Prevent cascading failures with typed circuit breakers:

```elixir
defmodule CircuitBreaker do
  use GenServer
  use Jido.TypeContract
  
  defcontract :breaker_config do
    required :failure_threshold, :integer, min: 1
    required :timeout_ms, :integer, min: 100
    required :reset_timeout_ms, :integer, min: 1000
  end
  
  defcontract :breaker_state do
    required :status, :atom, in: [:closed, :open, :half_open]
    required :failure_count, :integer, min: 0
    required :last_failure, :datetime, nullable: true
    required :config, :breaker_config
  end
  
  def call(breaker, fun) do
    GenServer.call(breaker, {:call, fun})
  end
  
  def handle_call({:call, fun}, _from, state) do
    case state.status do
      :open ->
        if should_attempt_reset?(state) do
          attempt_call(fun, %{state | status: :half_open})
        else
          error = Jido.Error.new(%{
            type: :circuit_open,
            message: "Circuit breaker is open",
            details: %{
              failure_count: state.failure_count,
              last_failure: state.last_failure
            }
          })
          {:reply, {:error, error}, state}
        end
        
      status when status in [:closed, :half_open] ->
        attempt_call(fun, state)
    end
  end
  
  defp attempt_call(fun, state) do
    try do
      case fun.() do
        {:ok, _} = result ->
          new_state = reset_breaker(state)
          {:reply, result, new_state}
        {:error, error} ->
          new_state = record_failure(state, error)
          {:reply, {:error, error}, new_state}
      end
    catch
      kind, reason ->
        error = Jido.Error.execution_error(
          "Circuit breaker caught exception",
          %{kind: kind, reason: reason}
        )
        new_state = record_failure(state, error)
        {:reply, {:error, error}, new_state}
    end
  end
end
```

### Error Aggregation Pipeline

Aggregate errors from multiple operations:

```elixir
defmodule ErrorAggregationPipeline do
  use Jido.TypeContract
  
  defcontract :pipeline_result do
    one_of [
      {:ok, :map},
      {:error, {:list, Jido.Error}},
      {:partial, :map, {:list, Jido.Error}}
    ]
  end
  
  def execute_pipeline(operations, initial_data) do
    results = Enum.reduce(operations, {[], initial_data}, fn operation, {errors, data} ->
      case operation.(data) do
        {:ok, new_data} ->
          {errors, Map.merge(data, new_data)}
        {:error, error} ->
          {[error | errors], data}
      end
    end)
    
    case results do
      {[], final_data} ->
        {:ok, final_data}
      {errors, partial_data} when map_size(partial_data) > map_size(initial_data) ->
        {:partial, partial_data, Enum.reverse(errors)}
      {errors, _} ->
        {:error, Enum.reverse(errors)}
    end
  end
  
  # Usage
  def process_user_registration(params) do
    operations = [
      &validate_user_data/1,
      &check_email_uniqueness/1,
      &create_user_record/1,
      &send_welcome_email/1,
      &create_initial_preferences/1
    ]
    
    case execute_pipeline(operations, params) do
      {:ok, result} ->
        {:ok, result}
      {:partial, result, errors} ->
        # Some operations succeeded
        log_partial_success(result, errors)
        {:ok, result}  # Or handle as needed
      {:error, errors} ->
        {:error, aggregate_errors(errors)}
    end
  end
end
```

## Testing Error Handling

### Contract-Based Error Testing

```elixir
defmodule ErrorContractTest do
  use ExUnit.Case
  use Jido.ContractTesting
  
  describe "error contracts" do
    test "validates error structure" do
      error = Jido.Error.validation_error("Invalid input", [
        %{field: :email, error: "is invalid"}
      ])
      
      assert %Jido.Error{
        type: :validation_error,
        message: "Invalid input",
        details: %{violations: _}
      } = error
      
      # Verify error contract
      assert_valid_contract(Jido.Error, :error_params, %{
        type: error.type,
        message: error.message,
        details: error.details
      })
    end
    
    test "error transformation preserves type safety" do
      original_error = Jido.Error.not_found("User", "123")
      
      http_response = ErrorTransformation.to_http_response({:error, original_error})
      
      assert http_response.status == 404
      assert http_response.body.error.type == :not_found
    end
  end
end
```

### Property-Based Error Testing

```elixir
defmodule ErrorPropertyTest do
  use ExUnit.Case
  use ExUnitProperties
  
  property "all error types have appropriate HTTP status codes" do
    check all error_type <- member_of([
      :validation_error, :authorization_error, :not_found,
      :conflict, :timeout, :system_error
    ]) do
      error = Jido.Error.new(%{
        type: error_type,
        message: "Test error"
      })
      
      response = ErrorTransformation.to_http_response({:error, error})
      
      assert response.status in 400..599
      assert is_map(response.body)
    end
  end
  
  property "error context enrichment preserves original error" do
    check all context <- map_of(atom(:alphanumeric), term()) do
      original_error = Jido.Error.system_error("Test", %{})
      
      enriched = ErrorContextEnrichment.ContextualError.with_context(
        {:error, original_error},
        context
      )
      
      assert {:error, %Jido.Error{} = error} = enriched
      assert error.message == original_error.message
      assert error.type == original_error.type
      
      for {key, value} <- context do
        assert error.context[key] == value
      end
    end
  end
end
```

## Error Monitoring and Observability

```elixir
defmodule ErrorObservability do
  @moduledoc """
  Provides error monitoring and alerting capabilities.
  """
  
  def setup_error_telemetry do
    :telemetry.attach_many(
      "error-monitoring",
      [
        [:jido, :error, :validation],
        [:jido, :error, :execution],
        [:jido, :error, :boundary]
      ],
      &handle_error_event/4,
      nil
    )
  end
  
  defp handle_error_event(event, measurements, metadata, _config) do
    error = metadata.error
    
    # Log structured error data
    Logger.error("""
    Error occurred: #{error.type}
    Message: #{error.message}
    Details: #{inspect(error.details)}
    Context: #{inspect(error.context)}
    """)
    
    # Send to monitoring service
    send_to_monitoring(error, event)
    
    # Alert on critical errors
    maybe_send_alert(error)
  end
  
  defp maybe_send_alert(%Jido.Error{type: type} = error) 
    when type in [:system_error, :timeout] do
    
    Alert.send(%{
      level: :critical,
      title: "Critical error in #{error.context[:boundary]}",
      details: error
    })
  end
  defp maybe_send_alert(_), do: :ok
end
```

## Summary

Type-safe error handling provides:

1. **Clear Error Boundaries**: Errors are caught and typed at system boundaries
2. **Structured Error Information**: Rich error types with context
3. **Avoid Antipatterns**: No defensive programming or complex error handling
4. **Better Debugging**: Clear error traces with context
5. **Graceful Degradation**: Recovery strategies and partial success handling
6. **Type Safety**: Errors maintain type information throughout the system

By implementing these patterns, you create systems that fail gracefully, provide clear error information, and maintain type safety even in error conditions.