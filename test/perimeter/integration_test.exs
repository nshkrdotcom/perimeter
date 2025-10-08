defmodule Perimeter.IntegrationTest do
  use ExUnit.Case, async: true

  describe "real-world scenario: user registration" do
    defmodule UserRegistration do
      use Perimeter

      defcontract :registration_params do
        required(:email, :string, format: ~r/@/)
        required(:password, :string, min_length: 12)

        optional :profile, :map do
          optional(:name, :string, max_length: 100)
          optional(:age, :integer, min: 18, max: 150)
          optional(:bio, :string, max_length: 500)
        end
      end

      @guard input: :registration_params
      def register(params) do
        # Simulate user creation
        {:ok,
         %{
           id: "user_#{:rand.uniform(1000)}",
           email: params.email,
           profile: Map.get(params, :profile, %{})
         }}
      end
    end

    test "successful registration with minimal fields" do
      result =
        UserRegistration.register(%{
          email: "user@example.com",
          password: "supersecret123"
        })

      assert {:ok, user} = result
      assert user.email == "user@example.com"
      assert user.profile == %{}
    end

    test "successful registration with complete profile" do
      result =
        UserRegistration.register(%{
          email: "user@example.com",
          password: "supersecret123",
          profile: %{
            name: "Alice Smith",
            age: 30,
            bio: "Software engineer"
          }
        })

      assert {:ok, user} = result
      assert user.email == "user@example.com"
      assert user.profile.name == "Alice Smith"
      assert user.profile.age == 30
    end

    test "rejects invalid email format" do
      error =
        assert_raise Perimeter.ValidationError, fn ->
          UserRegistration.register(%{
            email: "invalid-email",
            password: "supersecret123"
          })
        end

      assert error.message =~ "Validation failed"
      assert [violation] = error.violations
      assert violation.field == :email
      assert violation.error =~ "does not match format"
    end

    test "rejects password too short" do
      error =
        assert_raise Perimeter.ValidationError, fn ->
          UserRegistration.register(%{
            email: "user@example.com",
            password: "short"
          })
        end

      assert [violation] = error.violations
      assert violation.field == :password
      assert violation.error =~ "minimum length"
    end

    test "rejects underage user in profile" do
      error =
        assert_raise Perimeter.ValidationError, fn ->
          UserRegistration.register(%{
            email: "user@example.com",
            password: "supersecret123",
            profile: %{age: 17}
          })
        end

      assert [violation] = error.violations
      assert violation.field == :age
      assert violation.path == [:profile]
      assert violation.error =~ "minimum value"
    end

    test "rejects profile name too long" do
      long_name = String.duplicate("a", 101)

      error =
        assert_raise Perimeter.ValidationError, fn ->
          UserRegistration.register(%{
            email: "user@example.com",
            password: "supersecret123",
            profile: %{name: long_name}
          })
        end

      assert [violation] = error.violations
      assert violation.field == :name
      assert violation.path == [:profile]
      assert violation.error =~ "maximum length"
    end

    test "reports multiple violations at once" do
      error =
        assert_raise Perimeter.ValidationError, fn ->
          UserRegistration.register(%{
            email: "invalid",
            password: "short",
            profile: %{age: 17}
          })
        end

      assert length(error.violations) == 3
      fields = Enum.map(error.violations, & &1.field)
      assert :email in fields
      assert :password in fields
      assert :age in fields
    end
  end

  describe "real-world scenario: API request handling" do
    defmodule APIHandler do
      use Perimeter

      defcontract :search_params do
        required(:query, :string, min_length: 1)

        optional :filters, :map do
          optional(:category, :atom, in: [:all, :active, :archived])
          optional(:limit, :integer, min: 1, max: 100)
          optional(:offset, :integer, min: 0)
        end

        optional :sort, :map do
          required(:field, :atom, in: [:name, :created_at, :updated_at])
          required(:direction, :atom, in: [:asc, :desc])
        end
      end

      @guard input: :search_params
      def search(params) do
        query = params.query
        filters = Map.get(params, :filters, %{})
        sort = Map.get(params, :sort, %{field: :created_at, direction: :desc})

        {:ok,
         %{
           query: query,
           category: Map.get(filters, :category, :all),
           limit: Map.get(filters, :limit, 10),
           offset: Map.get(filters, :offset, 0),
           sort: sort
         }}
      end
    end

    test "search with defaults" do
      assert {:ok, result} = APIHandler.search(%{query: "test"})
      assert result.query == "test"
      assert result.category == :all
      assert result.limit == 10
      assert result.offset == 0
      assert result.sort == %{field: :created_at, direction: :desc}
    end

    test "search with custom filters" do
      result =
        APIHandler.search(%{
          query: "test",
          filters: %{
            category: :active,
            limit: 50,
            offset: 10
          }
        })

      assert {:ok, %{category: :active, limit: 50, offset: 10}} = result
    end

    test "search with custom sort" do
      result =
        APIHandler.search(%{
          query: "test",
          sort: %{field: :name, direction: :asc}
        })

      assert {:ok, %{sort: %{field: :name, direction: :asc}}} = result
    end

    test "rejects invalid category" do
      error =
        assert_raise Perimeter.ValidationError, fn ->
          APIHandler.search(%{
            query: "test",
            filters: %{category: :invalid}
          })
        end

      assert [violation] = error.violations
      assert violation.field == :category
      assert violation.path == [:filters]
    end

    test "rejects limit out of range" do
      error =
        assert_raise Perimeter.ValidationError, fn ->
          APIHandler.search(%{
            query: "test",
            filters: %{limit: 200}
          })
        end

      assert [violation] = error.violations
      assert violation.field == :limit
      assert violation.error =~ "maximum value"
    end

    test "rejects empty query" do
      error =
        assert_raise Perimeter.ValidationError, fn ->
          APIHandler.search(%{query: ""})
        end

      assert [violation] = error.violations
      assert violation.field == :query
      assert violation.error =~ "minimum length"
    end

    test "rejects invalid sort field" do
      error =
        assert_raise Perimeter.ValidationError, fn ->
          APIHandler.search(%{
            query: "test",
            sort: %{field: :invalid, direction: :asc}
          })
        end

      assert [violation] = error.violations
      assert violation.field == :field
      assert violation.path == [:sort]
    end

    test "rejects incomplete sort specification" do
      error =
        assert_raise Perimeter.ValidationError, fn ->
          APIHandler.search(%{
            query: "test",
            sort: %{field: :name}
          })
        end

      assert [violation] = error.violations
      assert violation.field == :direction
      assert violation.path == [:sort]
      assert violation.error == "is required"
    end
  end

  describe "real-world scenario: data processing pipeline" do
    defmodule DataProcessor do
      use Perimeter

      defcontract :process_input do
        required(:items, {:list, :map})
        required(:operation, :atom, in: [:transform, :filter, :aggregate])

        optional :options, :map do
          optional(:batch_size, :integer, min: 1, max: 1000)
          optional(:parallel, :boolean)
        end
      end

      @guard input: :process_input
      def process(params) do
        items = params.items
        operation = params.operation
        options = Map.get(params, :options, %{})

        processed_count = length(items)
        batch_size = Map.get(options, :batch_size, 100)

        {:ok,
         %{
           operation: operation,
           processed: processed_count,
           batch_size: batch_size
         }}
      end
    end

    test "processes items with defaults" do
      result =
        DataProcessor.process(%{
          items: [%{id: 1}, %{id: 2}],
          operation: :transform
        })

      assert {:ok, %{operation: :transform, processed: 2, batch_size: 100}} = result
    end

    test "processes with custom options" do
      result =
        DataProcessor.process(%{
          items: [%{id: 1}],
          operation: :filter,
          options: %{batch_size: 50, parallel: true}
        })

      assert {:ok, %{batch_size: 50}} = result
    end

    test "rejects invalid operation" do
      error =
        assert_raise Perimeter.ValidationError, fn ->
          DataProcessor.process(%{
            items: [%{id: 1}],
            operation: :invalid
          })
        end

      assert [violation] = error.violations
      assert violation.field == :operation
    end

    test "rejects non-map items in list" do
      error =
        assert_raise Perimeter.ValidationError, fn ->
          DataProcessor.process(%{
            items: [%{id: 1}, "not a map"],
            operation: :transform
          })
        end

      assert [violation] = error.violations
      assert violation.field == :items
      assert violation.error =~ "invalid list item"
    end

    test "rejects batch_size out of range" do
      error =
        assert_raise Perimeter.ValidationError, fn ->
          DataProcessor.process(%{
            items: [%{id: 1}],
            operation: :transform,
            options: %{batch_size: 2000}
          })
        end

      assert [violation] = error.violations
      assert violation.field == :batch_size
      assert violation.path == [:options]
    end
  end

  describe "real-world scenario: configuration management" do
    defmodule ConfigManager do
      use Perimeter

      defcontract :config do
        required(:service_name, :string, min_length: 1)
        required(:environment, :atom, in: [:dev, :staging, :production])

        required :database, :map do
          required(:host, :string)
          required(:port, :integer, min: 1, max: 65_535)
          required(:name, :string)
          optional(:pool_size, :integer, min: 1, max: 100)
        end

        optional :redis, :map do
          required(:host, :string)
          required(:port, :integer, min: 1, max: 65_535)
        end

        optional(:features, {:list, :atom})
      end

      @guard input: :config
      def validate_config(params) do
        {:ok, params}
      end
    end

    test "validates complete configuration" do
      config = %{
        service_name: "my-api",
        environment: :production,
        database: %{
          host: "localhost",
          port: 5432,
          name: "mydb",
          pool_size: 10
        },
        redis: %{
          host: "localhost",
          port: 6379
        },
        features: [:feature_a, :feature_b]
      }

      assert {:ok, ^config} = ConfigManager.validate_config(config)
    end

    test "validates minimal configuration" do
      config = %{
        service_name: "my-api",
        environment: :dev,
        database: %{
          host: "localhost",
          port: 5432,
          name: "mydb"
        }
      }

      assert {:ok, ^config} = ConfigManager.validate_config(config)
    end

    test "rejects invalid environment" do
      config = %{
        service_name: "my-api",
        environment: :test,
        database: %{host: "localhost", port: 5432, name: "mydb"}
      }

      error =
        assert_raise Perimeter.ValidationError, fn ->
          ConfigManager.validate_config(config)
        end

      assert [violation] = error.violations
      assert violation.field == :environment
    end

    test "rejects invalid database port" do
      config = %{
        service_name: "my-api",
        environment: :production,
        database: %{host: "localhost", port: 99_999, name: "mydb"}
      }

      error =
        assert_raise Perimeter.ValidationError, fn ->
          ConfigManager.validate_config(config)
        end

      assert [violation] = error.violations
      assert violation.field == :port
      assert violation.path == [:database]
    end

    test "rejects missing required nested field" do
      config = %{
        service_name: "my-api",
        environment: :production,
        database: %{host: "localhost", port: 5432}
      }

      error =
        assert_raise Perimeter.ValidationError, fn ->
          ConfigManager.validate_config(config)
        end

      assert [violation] = error.violations
      assert violation.field == :name
      assert violation.path == [:database]
    end
  end

  describe "dogfooding: Perimeter validates itself" do
    test "Perimeter.Validator.validate/3 validates its own inputs" do
      defmodule SelfValidatingContract do
        use Perimeter.Contract

        defcontract :test do
          required(:value, :integer)
        end
      end

      # Valid usage
      assert {:ok, _} = Perimeter.Validator.validate(SelfValidatingContract, :test, %{value: 42})

      # Invalid usage - non-map
      assert {:error, violations} =
               Perimeter.Validator.validate(SelfValidatingContract, :test, "not a map")

      assert [%{field: :_root}] = violations

      # Invalid usage - missing contract
      assert {:error, violations} =
               Perimeter.Validator.validate(SelfValidatingContract, :nonexistent, %{})

      assert [%{field: :_contract}] = violations
    end
  end
end
