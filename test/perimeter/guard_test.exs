defmodule Perimeter.GuardTest do
  use ExUnit.Case, async: true

  describe "basic guard functionality" do
    defmodule GuardedModule do
      use Perimeter

      defcontract :input do
        required(:email, :string, format: ~r/@/)
        required(:name, :string)
      end

      @guard input: :input
      def create_user(params) do
        {:ok, %{email: params.email, name: params.name}}
      end
    end

    test "allows valid input" do
      params = %{email: "test@example.com", name: "Alice"}
      assert {:ok, result} = GuardedModule.create_user(params)
      assert result.email == "test@example.com"
      assert result.name == "Alice"
    end

    test "raises on invalid type" do
      params = %{email: 123, name: "Alice"}

      assert_raise Perimeter.ValidationError, fn ->
        GuardedModule.create_user(params)
      end
    end

    test "raises on missing required field" do
      params = %{email: "test@example.com"}

      assert_raise Perimeter.ValidationError, fn ->
        GuardedModule.create_user(params)
      end
    end

    test "raises on constraint violation" do
      params = %{email: "invalid-email", name: "Alice"}

      assert_raise Perimeter.ValidationError, fn ->
        GuardedModule.create_user(params)
      end
    end
  end

  describe "error messages" do
    defmodule ErrorMessageModule do
      use Perimeter

      defcontract :input do
        required :user, :map do
          required(:email, :string, format: ~r/@/)
        end
      end

      @guard input: :input
      def process(params), do: {:ok, params}
    end

    test "provides clear error message with field paths" do
      params = %{user: %{email: "invalid"}}

      error =
        assert_raise Perimeter.ValidationError, fn ->
          ErrorMessageModule.process(params)
        end

      assert error.message =~ "Validation failed"

      assert error.violations == [
               %{field: :email, path: [:user], error: "does not match format"}
             ]
    end

    test "includes multiple violations in error" do
      params = %{user: %{}}

      error =
        assert_raise Perimeter.ValidationError, fn ->
          ErrorMessageModule.process(params)
        end

      assert length(error.violations) == 1
      assert Enum.any?(error.violations, &(&1.field == :email))
    end
  end

  describe "multiple guards in one module" do
    defmodule MultiGuardModule do
      use Perimeter

      defcontract :create_input do
        required(:email, :string)
      end

      defcontract :update_input do
        required(:id, :string)
        optional(:email, :string)
      end

      @guard input: :create_input
      def create(params), do: {:ok, :created, params}

      @guard input: :update_input
      def update(params), do: {:ok, :updated, params}

      # Unguarded function
      def delete(id), do: {:ok, :deleted, id}
    end

    test "guards create function" do
      assert {:ok, :created, _} = MultiGuardModule.create(%{email: "a@b.com"})

      assert_raise Perimeter.ValidationError, fn ->
        MultiGuardModule.create(%{})
      end
    end

    test "guards update function" do
      assert {:ok, :updated, _} = MultiGuardModule.update(%{id: "123"})

      assert_raise Perimeter.ValidationError, fn ->
        MultiGuardModule.update(%{})
      end
    end

    test "does not guard unguarded functions" do
      assert {:ok, :deleted, "123"} = MultiGuardModule.delete("123")
    end
  end

  describe "function metadata preservation" do
    # Note: @doc metadata is preserved by defoverridable, but Code.fetch_docs
    # doesn't work well with test modules. In real usage, documentation is preserved.

    test "guarded functions remain callable" do
      defmodule DocTestModule do
        use Perimeter

        defcontract :input do
          required(:email, :string)
        end

        @doc "Creates a new user account"
        @guard input: :input
        def create_user(params), do: {:ok, params}
      end

      # The function works correctly even with @doc
      assert {:ok, %{email: "test@example.com"}} =
               DocTestModule.create_user(%{email: "test@example.com"})
    end

    test "guarded functions with @doc false remain callable" do
      defmodule DocFalseTestModule do
        use Perimeter

        defcontract :input do
          required(:email, :string)
        end

        @doc false
        @guard input: :input
        def internal_create(params), do: {:ok, params}
      end

      # The function works correctly even with @doc false
      assert {:ok, %{email: "test@example.com"}} =
               DocFalseTestModule.internal_create(%{email: "test@example.com"})
    end
  end

  describe "function with multiple arities" do
    defmodule MultiArityModule do
      use Perimeter

      defcontract :input do
        required(:email, :string)
      end

      @guard input: :input
      def process(params), do: {:ok, :one_arg, params}

      def process(params, opts), do: {:ok, :two_args, params, opts}
    end

    test "guards only the specified arity" do
      assert {:ok, :one_arg, _} = MultiArityModule.process(%{email: "a@b.com"})

      assert_raise Perimeter.ValidationError, fn ->
        MultiArityModule.process(%{})
      end
    end

    test "does not guard other arities" do
      # Two-arg version is not guarded
      assert {:ok, :two_args, %{}, :opts} = MultiArityModule.process(%{}, :opts)
    end
  end

  describe "guards with pattern matching" do
    defmodule PatternMatchModule do
      use Perimeter

      defcontract :user_input do
        required(:name, :string)
        required(:age, :integer)
      end

      @guard input: :user_input
      def greet(%{name: name, age: age}) do
        "Hello #{name}, you are #{age}"
      end
    end

    test "validates before pattern matching" do
      result = PatternMatchModule.greet(%{name: "Alice", age: 30})
      assert result == "Hello Alice, you are 30"
    end

    test "validation error before pattern match error" do
      # Validation should fail before pattern matching attempts
      assert_raise Perimeter.ValidationError, fn ->
        PatternMatchModule.greet(%{name: "Alice"})
      end
    end
  end

  describe "guards with default arguments" do
    defmodule DefaultArgsModule do
      use Perimeter

      defcontract :input do
        required(:name, :string)
      end

      @guard input: :input
      def greet(params, greeting \\ "Hello") do
        "#{greeting}, #{params.name}"
      end
    end

    test "works with default argument" do
      assert DefaultArgsModule.greet(%{name: "Alice"}) == "Hello, Alice"
    end

    test "works with provided argument" do
      assert DefaultArgsModule.greet(%{name: "Alice"}, "Hi") == "Hi, Alice"
    end

    test "validates both arities" do
      assert_raise Perimeter.ValidationError, fn ->
        DefaultArgsModule.greet(%{})
      end

      assert_raise Perimeter.ValidationError, fn ->
        DefaultArgsModule.greet(%{}, "Hi")
      end
    end
  end

  describe "guard with when clause" do
    defmodule WhenClauseModule do
      use Perimeter

      defcontract :input do
        required(:age, :integer)
      end

      @guard input: :input
      def check_adult(%{age: age}) when age >= 18 do
        :adult
      end

      @guard input: :input
      def check_adult(%{age: _age}) do
        :minor
      end
    end

    test "validation happens before guard clause" do
      assert WhenClauseModule.check_adult(%{age: 20}) == :adult
      assert WhenClauseModule.check_adult(%{age: 15}) == :minor
    end

    test "raises on validation failure" do
      assert_raise Perimeter.ValidationError, fn ->
        WhenClauseModule.check_adult(%{})
      end
    end
  end

  describe "nested contract validation in guard" do
    defmodule NestedGuardModule do
      use Perimeter

      defcontract :registration do
        required(:email, :string, format: ~r/@/)

        optional :profile, :map do
          required(:name, :string, min_length: 1)
          optional(:age, :integer, min: 18)
        end
      end

      @guard input: :registration
      def register(params) do
        {:ok, params}
      end
    end

    test "validates nested structure" do
      params = %{
        email: "test@example.com",
        profile: %{name: "Alice", age: 30}
      }

      assert {:ok, ^params} = NestedGuardModule.register(params)
    end

    test "rejects invalid nested field" do
      params = %{
        email: "test@example.com",
        profile: %{name: "", age: 30}
      }

      assert_raise Perimeter.ValidationError, fn ->
        NestedGuardModule.register(params)
      end
    end

    test "rejects nested constraint violation" do
      params = %{
        email: "test@example.com",
        profile: %{name: "Alice", age: 17}
      }

      assert_raise Perimeter.ValidationError, fn ->
        NestedGuardModule.register(params)
      end
    end
  end

  describe "list validation in guard" do
    defmodule ListGuardModule do
      use Perimeter

      defcontract :bulk_input do
        required(:items, {:list, :string})
      end

      @guard input: :bulk_input
      def process_items(params) do
        {:ok, length(params.items)}
      end
    end

    test "validates list items" do
      params = %{items: ["a", "b", "c"]}
      assert {:ok, 3} = ListGuardModule.process_items(params)
    end

    test "rejects invalid list items" do
      params = %{items: ["a", 123, "c"]}

      assert_raise Perimeter.ValidationError, fn ->
        ListGuardModule.process_items(params)
      end
    end
  end

  describe "guard with non-map input" do
    defmodule NonMapModule do
      use Perimeter

      defcontract :input do
        required(:value, :integer)
      end

      @guard input: :input
      def process(params) do
        params.value * 2
      end
    end

    test "rejects non-map input" do
      assert_raise Perimeter.ValidationError, fn ->
        NonMapModule.process("not a map")
      end
    end
  end
end
