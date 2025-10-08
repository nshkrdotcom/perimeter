# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-10-07

### Added - Initial MVP Release 🎉

This is the first functional release of Perimeter, implementing the core "Defensive Perimeter / Offensive Interior" pattern for Elixir.

#### Core Features

- **Contract DSL** (`Perimeter.Contract`)
  - `defcontract` macro for defining data contracts
  - `required/3` and `optional/3` field definitions
  - Support for all basic Elixir types (string, integer, float, boolean, atom, map, list)
  - Typed lists with `{:list, type}` syntax
  - Nested field definitions with unlimited depth

- **Validation Engine** (`Perimeter.Validator`)
  - `validate/3` function for runtime validation
  - Comprehensive type checking
  - Rich constraint validation (format, min/max, min_length/max_length, in:)
  - Nested map validation with full path tracking
  - Clear error messages with violation details
  - Multiple violation reporting

- **Guard Macro** (`Perimeter.Guard`)
  - `@guard` attribute for function-level enforcement
  - Automatic input validation before function execution
  - Raises `Perimeter.ValidationError` on validation failure
  - Supports multiple guards per module
  - Preserves function metadata (@doc, @spec, etc.)
  - Works with pattern matching, guards, and default arguments

- **Error Handling** (`Perimeter.ValidationError`)
  - Clear exception messages
  - Detailed violation information (field, error, path)
  - Formatted error output

#### Documentation

- Complete README with quick start guide
- Real-world usage examples (API, configuration, data processing)
- Module documentation with examples
- TDD implementation plan
- Critical review and validation reports

#### Testing

- 117 comprehensive tests (100% passing)
- 90.51% code coverage
- Integration tests for real-world scenarios
- Dogfooding (Perimeter validates itself)

#### Quality Assurance

- ✅ Zero compiler warnings
- ✅ Credo strict mode - no issues
- ✅ Dialyzer - no errors
- ✅ All code formatted with `mix format`
- ✅ All examples verified working

### Implementation Details

**Approach**: Test-Driven Development (TDD)
- Every feature written test-first
- Red-Green-Refactor cycle throughout
- 2.2:1 test-to-code ratio

**Architecture**:
- Three-zone model implementation
- Macro-based DSL for contracts
- Runtime validation engine
- Compile-time guard injection

### Known Limitations

The following features are intentionally not included in v0.1.0 (planned for future releases):

- Output contract validation (input only in MVP)
- Enforcement levels (`:log`, `:warn` - strict only in MVP)
- Validation result caching
- Performance optimizations
- Telemetry integration
- Ecto integration helpers
- Phoenix integration helpers
- Custom Credo checks
- `Perimeter.Interface` for Strategy pattern

### Migration Notes

This is the first release. No migration needed.

### Breaking Changes

None (initial release).

---

## [Unreleased]

### Planned for v0.2.0

- Output contract validation
- Enforcement levels (`:log`, `:warn`, `:strict`)
- Validation result caching for performance
- Telemetry events for monitoring
- Enhanced error messages with suggestions

### Planned for v0.3.0

- Ecto integration (`from_ecto_schema`)
- Phoenix controller helpers
- Custom validation functions
- `Perimeter.Interface` for Strategy pattern support

### Planned for v1.0.0

- Production-proven stability
- Custom Credo checks
- LiveDashboard integration
- Code generation tools (`mix perimeter.gen.spec`)
- Comprehensive migration guides

---

[0.1.0]: https://github.com/nshkrdotcom/perimeter/releases/tag/v0.1.0
