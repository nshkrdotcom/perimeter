# Perimeter Library Caching Strategies

## Overview

This document outlines caching strategies for the `perimeter` library to ensure minimal performance overhead while maintaining correctness. The caching system is designed to optimize repeated validations without sacrificing the safety guarantees of the defensive perimeter pattern.

## Core Caching Principles

### 1. Immutability Advantage
Elixir's immutable data structures make caching particularly effective:
- Once validated, a data structure cannot change
- Cache keys can be based on data identity
- No cache invalidation needed for validated data

### 2. Compile-Time vs Runtime Caching
The library employs both strategies:
- **Compile-time**: Contract compilation and optimization
- **Runtime**: Validation result caching

### 3. Memory vs CPU Trade-off
Caching decisions balance:
- Memory usage (storing validation results)
- CPU usage (recomputing validations)
- Cache lookup overhead

## Compile-Time Caching Strategies

### 1. Contract Compilation Cache

```elixir
defmodule Perimeter.Contract.Compiler do
  @moduledoc """
  Compiles contracts into optimized validation functions at compile time.
  """
  
  defmacro compile_contract(contract_definition) do
    # Generate optimized validator at compile time
    validator_ast = build_optimized_validator(contract_definition)
    
    quote do
      # Store compiled validator as module attribute
      @compiled_validators[unquote(contract_name)] = unquote(Macro.escape(validator_ast))
      
      # Generate fast validator function
      def __fast_validate__(unquote(contract_name), data) do
        unquote(validator_ast)
      end
    end
  end
  
  defp build_optimized_validator(contract) do
    # Convert contract to optimized pattern matches
    # This runs at compile time, not runtime
    quote do
      case data do
        %{unquote_splicing(required_field_patterns(contract))} ->
          # Inline type checks
          unquote(generate_type_checks(contract))
        _ ->
          {:error, :missing_required_fields}
      end
    end
  end
end
```

### 2. Pattern Match Optimization

```elixir
defmodule Perimeter.Contract.PatternOptimizer do
  @moduledoc """
  Optimizes contracts into efficient pattern matches.
  """
  
  def optimize_contract(contract) do
    contract
    |> group_by_type()
    |> generate_type_specific_validators()
    |> compile_to_beam_friendly_form()
  end
  
  # Group fields by type for batch validation
  defp group_by_type(contract) do
    contract.fields
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, fields} ->
      {type, optimize_type_check(type, fields)}
    end)
  end
  
  # Generate specialized validators per type
  defp optimize_type_check(:string, fields) do
    # Single pass string validation for all string fields
    quote do
      Enum.all?(unquote(fields), fn field ->
        is_binary(Map.get(data, field.name))
      end)
    end
  end
end
```

## Runtime Caching Strategies

### 1. Validation Result Cache

```elixir
defmodule Perimeter.Cache do
  @moduledoc """
  ETS-based cache for validation results with configurable TTL.
  """
  
  use GenServer
  
  @table_name :perimeter_validation_cache
  @default_ttl :infinity
  @max_cache_size 10_000
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    table = :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])
    
    state = %{
      table: table,
      ttl: Keyword.get(opts, :ttl, @default_ttl),
      max_size: Keyword.get(opts, :max_size, @max_cache_size),
      size: 0,
      hits: 0,
      misses: 0
    }
    
    {:ok, state}
  end
  
  @doc """
  Cache-aware validation with TTL support.
  """
  def validate_with_cache(module, contract, data, opts \ []) do
    cache_key = compute_cache_key(module, contract, data)
    
    case lookup_cache(cache_key) do
      {:ok, cached_result} ->
        bump_stats(:hit)
        cached_result
        
      :miss ->
        bump_stats(:miss)
        result = Perimeter.Validator.validate_direct(module, contract, data)
        cache_result(cache_key, result, opts)
        result
    end
  end
  
  defp compute_cache_key(module, contract, data) do
    # Use :erlang.phash2 for fast, stable hashing
    :erlang.phash2({module, contract, data})
  end
  
  defp lookup_cache(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, result, expiry}] when expiry > System.monotonic_time() ->
        {:ok, result}
      _ ->
        :miss
    end
  end
  
  defp cache_result(key, result, opts) do
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    expiry = case ttl do
      :infinity -> :infinity
      ms -> System.monotonic_time() + ms * 1_000_000
    end
    
    GenServer.cast(__MODULE__, {:cache, key, result, expiry})
  end
  
  def handle_cast({:cache, key, result, expiry}, state) do
    # Implement LRU eviction if needed
    state = maybe_evict_entries(state)
    
    :ets.insert(@table_name, {key, result, expiry})
    {:noreply, %{state | size: state.size + 1}}
  end
  
  defp maybe_evict_entries(%{size: size, max_size: max} = state) when size >= max do
    # Simple FIFO eviction for now
    # Could implement LRU with additional timestamp tracking
    oldest_key = :ets.first(@table_name)
    :ets.delete(@table_name, oldest_key)
    %{state | size: size - 1}
  end
  defp maybe_evict_entries(state), do: state
end
```

### 2. Partial Validation Cache

```elixir
defmodule Perimeter.Cache.Partial do
  @moduledoc """
  Caches validation results for parts of nested structures.
  """
  
  def validate_with_partial_cache(data, contract) do
    case data do
      %{__cached_validation__: token} ->
        # Check if this exact data was already validated
        lookup_validation_token(token)
        
      map when is_map(map) ->
        # Check cache for each nested structure
        validate_with_nested_cache(map, contract)
        
      _ ->
        # No caching for non-map data
        Perimeter.Validator.validate_direct(data, contract)
    end
  end
  
  defp validate_with_nested_cache(map, contract) do
    # Validate nested structures independently
    Enum.reduce_while(contract.fields, {:ok, %{}}, fn field, {:ok, acc} ->
      case validate_field_with_cache(map, field) do
        {:ok, value} ->
          {:cont, {:ok, Map.put(acc, field.name, value)}}
        {:error, _} = error ->
          {:halt, error}
      end
    end)
  end
end
```

### 3. Contract-Specific Caching

```elixir
defmodule Perimeter.Cache.ContractSpecific do
  @moduledoc """
  Provides contract-specific caching strategies.
  """
  
  defmacro enable_caching(contract_name, opts \ []) do
    strategy = Keyword.get(opts, :strategy, :full)
    ttl = Keyword.get(opts, :ttl, :timer.minutes(5))
    
    quote do
      @contract_cache_config[unquote(contract_name)] = %{
        strategy: unquote(strategy),
        ttl: unquote(ttl),
        enabled: true
      }
    end
  end
  
  # Different caching strategies per contract
  def cache_strategy(module, contract_name) do
    config = module.__contract_cache_config__(contract_name)
    
    case config.strategy do
      :full ->
        # Cache entire validation result
        &full_result_cache/3
        
      :fields ->
        # Cache individual field validations
        &field_level_cache/3
        
      :none ->
        # No caching for this contract
        &no_cache/3
    end
  end
end
```

## Cache Key Strategies

### 1. Content-Based Keys

```elixir
defmodule Perimeter.Cache.Keys do
  @moduledoc """
  Efficient cache key generation strategies.
  """
  
  # Fast hash for immutable data
  def content_hash(data) when is_map(data) do
    :erlang.phash2(data)
  end
  
  # Structural hash (ignores values, only structure)
  def structural_hash(data) when is_map(data) do
    data
    |> Map.keys()
    |> Enum.sort()
    |> :erlang.phash2()
  end
  
  # Hybrid approach for large data
  def smart_hash(data) when is_map(data) do
    if map_size(data) > 100 do
      # For large maps, hash structure + sample values
      sample_hash(data)
    else
      # For small maps, hash everything
      content_hash(data)
    end
  end
  
  defp sample_hash(data) do
    # Hash structure + first N values
    keys = Map.keys(data) |> Enum.sort() |> Enum.take(10)
    sample = Enum.map(keys, &{&1, Map.get(data, &1)})
    :erlang.phash2({keys, sample})
  end
end
```

### 2. Hierarchical Cache Keys

```elixir
defmodule Perimeter.Cache.Hierarchical do
  @moduledoc """
  Hierarchical caching for nested validations.
  """
  
  def build_cache_hierarchy(data, path \ []) do
    case data do
      map when is_map(map) ->
        # Build hierarchy of cache keys
        Enum.map(map, fn {key, value} ->
          child_path = path ++ [key]
          {
            cache_key: path_to_cache_key(child_path),
            value: value,
            children: build_cache_hierarchy(value, child_path)
          }
        end)
        
      list when is_list(list) ->
        # Cache list validations separately
        {
          cache_key: path_to_cache_key(path ++ [:__list__]),
          items: Enum.with_index(list)
        }
        
      _ ->
        nil
    end
  end
  
  defp path_to_cache_key(path) do
    :erlang.phash2(path)
  end
end
```

## Cache Warming Strategies

### 1. Compile-Time Warming

```elixir
defmodule Perimeter.Cache.Warming do
  @moduledoc """
  Pre-warm caches with common validations.
  """
  
  defmacro warm_cache(contract_name, examples) do
    quote do
      @on_load :warm_validation_cache
      
      def warm_validation_cache do
        # Validate examples at module load time
        Enum.each(unquote(examples), fn example ->
          Perimeter.Validator.validate(__MODULE__, unquote(contract_name), example)
        end)
        :ok
      end
    end
  end
end

# Usage
defmodule MyModule do
  use Perimeter.Contract
  
  defcontract :user do
    required :email, :string
    required :age, :integer
  end
  
  # Pre-validate common cases
  warm_cache :user, [
    %{email: "admin@example.com", age: 30},
    %{email: "user@example.com", age: 25}
  ]
end
```

### 2. Runtime Cache Warming

```elixir
defmodule Perimeter.Cache.RuntimeWarming do
  @moduledoc """
  Warms cache based on actual usage patterns.
  """
  
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Track validation patterns
    :ets.new(:perimeter_usage_patterns, [:set, :public, :named_table])
    
    # Periodically analyze and warm cache
    schedule_analysis()
    
    {:ok, %{}}
  end
  
  def track_validation(module, contract, data) do
    pattern = extract_pattern(data)
    :ets.update_counter(:perimeter_usage_patterns, {module, contract, pattern}, 1, {{module, contract, pattern}, 0})
  end
  
  defp extract_pattern(data) when is_map(data) do
    # Extract structural pattern
    data
    |> Map.keys()
    |> Enum.sort()
  end
  
  def handle_info(:analyze_patterns, state) do
    warm_frequent_patterns()
    schedule_analysis()
    {:noreply, state}
  end
  
  defp warm_frequent_patterns do
    :ets.tab2list(:perimeter_usage_patterns)
    |> Enum.filter(fn {{_mod, _contract, _pattern}, count} -> count > 100 end)
    |> Enum.each(fn {{mod, contract, pattern}, _count} ->
      # Generate and validate synthetic data matching pattern
      synthetic_data = generate_from_pattern(pattern)
      Perimeter.Validator.validate(mod, contract, synthetic_data)
    end)
  end
end
```

## Cache Invalidation Strategies

### 1. TTL-Based Invalidation

```elixir
defmodule Perimeter.Cache.TTL do
  @moduledoc """
  Time-based cache invalidation.
  """
  
  def cleanup_expired_entries do
    now = System.monotonic_time()
    
    # ETS match spec for expired entries
    match_spec = [
      {
        {:_,"$2",:"$3"},
        [{:<, :"$3", now}],
        [:"$1"]
      }
    ]
    
    expired_keys = :ets.select(:perimeter_validation_cache, match_spec)
    Enum.each(expired_keys, &:ets.delete(:perimeter_validation_cache, &1))
  end
  
  # Run periodically
  def schedule_cleanup do
    Process.send_after(self(), :cleanup, :timer.minutes(5))
  end
end
```

### 2. Memory-Pressure Invalidation

```elixir
defmodule Perimeter.Cache.MemoryPressure do
  @moduledoc """
  Responds to memory pressure by evicting cache entries.
  """
  
  def check_memory_pressure do
    case :erlang.memory(:total) do
      bytes when bytes > memory_threshold() ->
        evict_percentage(0.2) # Evict 20% of cache
        
      _ ->
        :ok
    end
  end
  
  defp memory_threshold do
    # 80% of system memory
    :erlang.system_info(:system_total_memory) * 0.8
  end
  
  defp evict_percentage(percent) do
    cache_size = :ets.info(:perimeter_validation_cache, :size)
    to_evict = trunc(cache_size * percent)
    
    # Evict oldest entries first
    :ets.foldl(
      fn entry, count when count < to_evict ->
        :ets.delete(:perimeter_validation_cache, elem(entry, 0))
        count + 1
      end,
      0,
      :perimeter_validation_cache
    )
  end
end
```

## Performance Monitoring

### 1. Cache Metrics

```elixir
defmodule Perimeter.Cache.Metrics do
  @moduledoc """
  Telemetry integration for cache monitoring.
  """
  
  def emit_cache_metrics do
    metrics = %{
      size: :ets.info(:perimeter_validation_cache, :size),
      memory: :ets.info(:perimeter_validation_cache, :memory),
      hit_rate: calculate_hit_rate(),
      avg_lookup_time: calculate_avg_lookup_time()
    }
    
    :telemetry.execute(
      [:perimeter, :cache, :snapshot],
      metrics,
      %{}
    )
  end
  
  def track_lookup(key, result, duration) do
    :telemetry.execute(
      [:perimeter, :cache, :lookup],
      %{duration: duration},
      %{key: key, result: result}
    )
  end
end
```

### 2. Adaptive Caching

```elixir
defmodule Perimeter.Cache.Adaptive do
  @moduledoc """
  Adapts caching strategy based on runtime metrics.
  """
  
  def should_cache?(module, contract, data_size) do
    stats = get_contract_stats(module, contract)
    
    # Cache if frequently validated or expensive
    stats.validation_count > 10 or
    stats.avg_validation_time > 1000 or  # 1ms
    data_size > 50  # Large data structures
  end
  
  def adjust_ttl(module, contract) do
    stats = get_contract_stats(module, contract)
    
    cond do
      # High frequency, long TTL
      stats.validations_per_minute > 100 ->
        :timer.hours(1)
        
      # Medium frequency
      stats.validations_per_minute > 10 ->
        :timer.minutes(10)
        
      # Low frequency, short TTL
      true ->
        :timer.minutes(1)
    end
  end
end
```

## Configuration Options

```elixir
# config/config.exs
config :perimeter,
  cache: [
    enabled: true,
    strategy: :ets,  # :ets | :persistent_term | :none
    max_size: 10_000,
    default_ttl: :timer.minutes(5),
    cleanup_interval: :timer.minutes(1),
    warm_cache_on_boot: true,
    compression: false  # Compress large cached values
  ]

# Per-environment configuration
config :perimeter, :prod,
  cache: [
    strategy: :persistent_term,  # Better for read-heavy production
    compression: true
  ]

config :perimeter, :test,
  cache: [
    enabled: false  # Disable caching in tests for predictability
  ]
```

## Best Practices

### 1. Cache Selection Guidelines

- **Always Cache**: Small, frequently validated contracts
- **Sometimes Cache**: Large data with expensive validations
- **Never Cache**: Contracts with time-sensitive validations

### 2. Memory Management

- Set reasonable TTLs based on usage patterns
- Monitor cache size and hit rates
- Implement memory-pressure responses
- Use compression for large cached values

### 3. Testing Considerations

- Disable caching in test environment by default
- Provide cache bypass options for debugging
- Test cache eviction strategies
- Verify cache correctness with property tests

## Summary

The caching strategy for `perimeter` leverages Elixir's immutability to provide efficient validation caching without sacrificing correctness. By combining compile-time optimization with runtime result caching, the library achieves minimal overhead while maintaining the strong guarantees of the defensive perimeter pattern.
