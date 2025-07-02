# Formal Type Relationships in Jido Framework

## Type Hierarchy and Relationships

### Core Type Definitions

| Type | Module | Definition | Purpose |
|------|--------|------------|---------|
| `action()` | `Jido.Action` | `module()` | Action behavior implementation |
| `agent()` | `Jido.Agent` | `%Jido.Agent{}` struct | Stateful workflow executor |
| `instruction()` | `Jido.Instruction` | `%Jido.Instruction{}` struct | Normalized work unit |
| `error()` | `Jido.Error` | `%Jido.Error{}` struct | Standardized error representation |
| `directive()` | `Jido.Agent.Directive` | `%{type, target, value}` | State modification instruction |

### Type Transformation Pipeline

| Stage | Input Type | Operation | Output Type | Contract |
|-------|------------|-----------|-------------|----------|
| 1 | `module \| {module, map}` | `Instruction.normalize/3` | `{:ok, [Instruction.t]}` | Module validation |
| 2 | `Instruction.t` | `Action.validate_params/1` | `{:ok, map} \| {:error, Error.t}` | Schema validation |
| 3 | `{params, context}` | `Action.run/2` | `action_result()` | Runtime execution |
| 4 | `action_result()` | `Action.validate_output/1` | `{:ok, map} \| {:error, Error.t}` | Output validation |
| 5 | `{:ok, map, directives}` | `Directive.apply/2` | `{:ok, agent()} \| {:error, Error.t}` | State application |

### Structural Type Relationships

#### Action Type Family

| Type | Structure | Constraints | Usage Context |
|------|-----------|-------------|---------------|
| `action_result()` | `{:ok, map()}` | Map keys match output_schema | Simple success |
| | `{:ok, map(), directive()}` | Map validated, directive well-formed | Success with side effects |
| | `{:ok, map(), [directive()]}` | Map validated, all directives valid | Success with multiple effects |
| | `{:error, Error.t()}` | Error has valid type | Simple failure |
| | `{:error, Error.t(), directive()}` | Error typed, directive for cleanup | Failure with compensation |

#### Agent Type Family

| Type | Structure | Constraints | Usage Context |
|------|-----------|-------------|---------------|
| `agent_result()` | `{:ok, Agent.t()}` | State validated against schema | Successful operation |
| | `{:error, Error.t()}` | Error indicates failure reason | Operation failure |
| `agent_state()` | `map()` | Validates against agent schema | Internal state storage |
| `pending_instructions()` | `:queue.queue()` | Contains valid instructions | Execution queue |

#### Instruction Type Family

| Type | Structure | Constraints | Usage Context |
|------|-----------|-------------|---------------|
| `instruction()` | `module()` | Must implement Action behavior | Simple action reference |
| | `{module(), map()}` | Module valid, params are map | Action with parameters |
| | `%Instruction{}` | All fields properly typed | Normalized instruction |
| `instruction_list()` | `[instruction()]` | No nested lists allowed | Batch operations |

### Type Validation Boundaries

| Boundary | Validated Types | Validation Method | Enforcement Level |
|----------|----------------|-------------------|-------------------|
| Action Entry | `params :: map()` | Schema validation | Strict |
| Action Exit | `result :: map()` | Output schema validation | Configurable |
| Agent State Change | `state :: map()` | State schema validation | Strict |
| Instruction Creation | `action :: module()` | Behavior implementation | Strict |
| Error Propagation | `error :: Error.t()` | Type field validation | Required |

### Cross-Module Type Dependencies

```
┌─────────────────────────────────────────────────────────────┐
│                     Type Dependency Graph                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Jido.Action ─────uses────> Jido.Error                     │
│      │                           ^                          │
│      │                           │                          │
│      └────produces───> action_result                       │
│                              │                              │
│                              │                              │
│  Jido.Instruction ───────────┘                             │
│      │                                                      │
│      └────references───> action :: module()                │
│                                                             │
│  Jido.Agent ─────contains───> Instruction.t()              │
│      │                                                      │
│      └────maintains───> state :: map()                     │
│                                                             │
│  Jido.Agent.Directive ───modifies───> Agent.state          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Type Coercion Rules

| From Type | To Type | Coercion Function | Safety |
|-----------|---------|-------------------|---------|
| `keyword()` | `map()` | `Map.new/1` | Safe |
| `any()` | `map()` | `validate_map_shape/1` | Validated |
| `String.t()` | `atom()` | `String.to_existing_atom/1` | Safe with guard |
| `{:ok, value}` | `value` | `unwrap_ok/1` | Checked |
| `module()` | `Instruction.t()` | `Instruction.new!/1` | Validated |

### Polymorphic Type Patterns

| Pattern | Type Expression | Runtime Behavior | Example |
|---------|-----------------|------------------|---------|
| Union Types | `{:ok, T} \| {:error, E}` | Pattern matching | Result tuples |
| Tagged Unions | `{tag :: atom(), value :: any()}` | Tag-based dispatch | Directives |
| Protocol Dispatch | `impl_for(module)` | Module-based polymorphism | Action behaviors |
| Parametric | `[T]` where T is consistent | List operations | Instruction lists |

### Type Contract Composition

| Composition Type | Definition | Example | Validation |
|-----------------|------------|---------|------------|
| Sequential | `A -> B -> C` | `params -> validated -> result` | Each step validated |
| Parallel | `{A, B, C}` | Multiple directives | All must succeed |
| Alternative | `A \| B \| C` | Result types | First match wins |
| Nested | `A<B<C>>` | `Agent<State<Map>>` | Recursive validation |

### Error Type Propagation

| Error Origin | Type | Propagation Path | Final Type |
|--------------|------|------------------|------------|
| Validation | `:validation_error` | Action -> Exec -> Agent | `{:error, Error.t()}` |
| Execution | `:execution_error` | Action runtime -> Exec | `{:error, Error.t()}` |
| Timeout | `:timeout` | Exec boundary -> Agent | `{:error, Error.t()}` |
| Planning | `:planning_error` | Agent planner -> Result | `{:error, Error.t()}` |

### Type Safety Guarantees

| Guarantee | Mechanism | Verification | Coverage |
|-----------|-----------|--------------|----------|
| Input Safety | Schema validation | Compile + Runtime | 100% of actions |
| Output Safety | Output validation | Runtime | Configurable |
| State Safety | State schema | Runtime | All state changes |
| Error Safety | Error type system | Compile-time | All error paths |
| Directive Safety | Type checking | Runtime | All directives |

### Type System Evolution Rules

| Change Type | Allowed | Migration Strategy | Risk Level |
|-------------|---------|-------------------|------------|
| Add optional field | ✓ | Backward compatible | Low |
| Add required field | ✗ | Major version bump | High |
| Change field type | ✗ | Adapter pattern | High |
| Add new error type | ✓ | Extend error union | Low |
| Remove field | ✗ | Deprecation cycle | High |
| Add type constraint | ~ | Gradual enforcement | Medium |

### Performance Characteristics

| Type Operation | Complexity | Optimization | Cache Strategy |
|----------------|------------|--------------|----------------|
| Schema validation | O(n) fields | Compile-time paths | Result caching |
| Type coercion | O(1) | Direct dispatch | Not needed |
| Error creation | O(1) | Struct allocation | Not cached |
| Directive application | O(1) | Pattern match | Not needed |
| Contract checking | O(n) rules | Rule compilation | Compiled contracts |

## Type Contract Verification Examples

### Action Contract Verification

```elixir
# Type: Action.run/2 :: (map(), map()) -> action_result()
# Contract: params match schema AND result matches output_schema

verify_action_contract(MyAction) ->
  # Input contract
  assert validate_params(sample_params) == {:ok, validated}
  
  # Execution contract  
  assert {:ok, result} = run(validated, context)
  
  # Output contract
  assert validate_output(result) == {:ok, result}
```

### Agent State Contract

```elixir
# Type: Agent.state :: map()
# Contract: state always validates against agent schema

verify_agent_state(agent) ->
  # State modification contract
  assert {:ok, new_agent} = set(agent, changes)
  assert validate_state(new_agent.state) == {:ok, _}
  
  # State invariants maintained
  assert map_size(new_agent.state) >= map_size(agent.state)
```

### Instruction Normalization Contract

```elixir
# Type: normalize/3 :: (various, map(), keyword()) -> {:ok, [Instruction.t()]}
# Contract: Always returns list of valid instructions

verify_instruction_normalization() ->
  # Module normalization
  assert {:ok, [%Instruction{action: Mod}]} = normalize(Mod)
  
  # Tuple normalization  
  assert {:ok, [%Instruction{params: params}]} = normalize({Mod, params})
  
  # List normalization
  assert {:ok, instructions} = normalize([Mod1, {Mod2, params}])
  assert length(instructions) == 2
```