defmodule Perimeter.ValidatorTest do
  use ExUnit.Case, async: true
  alias Perimeter.Validator

  describe "type validation" do
    defmodule TypeContract do
      use Perimeter.Contract

      defcontract :types do
        required(:string_field, :string)
        required(:integer_field, :integer)
        required(:float_field, :float)
        required(:boolean_field, :boolean)
        required(:atom_field, :atom)
        required(:map_field, :map)
        required(:list_field, :list)
      end
    end

    test "validates correct types" do
      data = %{
        string_field: "hello",
        integer_field: 42,
        float_field: 3.14,
        boolean_field: true,
        atom_field: :ok,
        map_field: %{},
        list_field: []
      }

      assert {:ok, ^data} = Validator.validate(TypeContract, :types, data)
    end

    test "rejects incorrect string type" do
      data = %{
        string_field: 123,
        integer_field: 42,
        float_field: 3.14,
        boolean_field: true,
        atom_field: :ok,
        map_field: %{},
        list_field: []
      }

      assert {:error, violations} = Validator.validate(TypeContract, :types, data)
      assert [%{field: :string_field, error: error}] = violations
      assert error =~ "expected string"
    end

    test "rejects incorrect integer type" do
      data = %{
        string_field: "hello",
        integer_field: "not an integer",
        float_field: 3.14,
        boolean_field: true,
        atom_field: :ok,
        map_field: %{},
        list_field: []
      }

      assert {:error, violations} = Validator.validate(TypeContract, :types, data)
      assert [%{field: :integer_field, error: error}] = violations
      assert error =~ "expected integer"
    end

    test "rejects incorrect boolean type" do
      data = %{
        string_field: "hello",
        integer_field: 42,
        float_field: 3.14,
        boolean_field: "yes",
        atom_field: :ok,
        map_field: %{},
        list_field: []
      }

      assert {:error, violations} = Validator.validate(TypeContract, :types, data)
      assert [%{field: :boolean_field, error: error}] = violations
      assert error =~ "expected boolean"
    end

    test "reports multiple type violations" do
      data = %{
        string_field: 123,
        integer_field: "wrong",
        float_field: 3.14,
        boolean_field: true,
        atom_field: :ok,
        map_field: %{},
        list_field: []
      }

      assert {:error, violations} = Validator.validate(TypeContract, :types, data)
      assert length(violations) == 2

      fields = Enum.map(violations, & &1.field)
      assert :string_field in fields
      assert :integer_field in fields
    end
  end

  describe "required field validation" do
    defmodule RequiredContract do
      use Perimeter.Contract

      defcontract :user do
        required(:email, :string)
        required(:password, :string)
        optional(:name, :string)
      end
    end

    test "validates when all required fields present" do
      data = %{email: "test@example.com", password: "secret"}
      assert {:ok, _} = Validator.validate(RequiredContract, :user, data)
    end

    test "rejects missing required field" do
      data = %{email: "test@example.com"}
      assert {:error, violations} = Validator.validate(RequiredContract, :user, data)

      assert [%{field: :password, error: "is required"}] = violations
    end

    test "allows missing optional fields" do
      data = %{email: "test@example.com", password: "secret"}
      assert {:ok, _} = Validator.validate(RequiredContract, :user, data)
    end

    test "validates optional fields when present" do
      data = %{email: "test@example.com", password: "secret", name: 123}
      assert {:error, violations} = Validator.validate(RequiredContract, :user, data)

      assert [%{field: :name, error: error}] = violations
      assert error =~ "expected string"
    end

    test "reports multiple missing required fields" do
      data = %{}
      assert {:error, violations} = Validator.validate(RequiredContract, :user, data)

      assert length(violations) == 2
      fields = Enum.map(violations, & &1.field)
      assert :email in fields
      assert :password in fields
    end
  end

  describe "string constraints" do
    defmodule StringContract do
      use Perimeter.Contract

      defcontract :format_test do
        required(:email, :string, format: ~r/@/)
      end

      defcontract :length_test do
        required(:short, :string, min_length: 3)
        required(:long, :string, max_length: 10)
        required(:bounded, :string, min_length: 5, max_length: 15)
      end
    end

    test "validates format with regex" do
      data = %{email: "user@example.com"}
      assert {:ok, _} = Validator.validate(StringContract, :format_test, data)
    end

    test "rejects format mismatch" do
      data = %{email: "invalid-email"}
      assert {:error, violations} = Validator.validate(StringContract, :format_test, data)

      assert [%{field: :email, error: error}] = violations
      assert error =~ "does not match format"
    end

    test "validates min_length" do
      data = %{short: "abc", long: "test", bounded: "hello"}
      assert {:ok, _} = Validator.validate(StringContract, :length_test, data)
    end

    test "rejects string too short" do
      data = %{short: "ab", long: "test", bounded: "hello"}
      assert {:error, violations} = Validator.validate(StringContract, :length_test, data)

      assert [%{field: :short, error: error}] = violations
      assert error =~ "minimum length"
    end

    test "validates max_length" do
      data = %{short: "abc", long: "1234567890", bounded: "hello"}
      assert {:ok, _} = Validator.validate(StringContract, :length_test, data)
    end

    test "rejects string too long" do
      data = %{short: "abc", long: "12345678901", bounded: "hello"}
      assert {:error, violations} = Validator.validate(StringContract, :length_test, data)

      assert [%{field: :long, error: error}] = violations
      assert error =~ "maximum length"
    end

    test "validates bounded length" do
      data = %{short: "abc", long: "test", bounded: "hello world"}
      assert {:ok, _} = Validator.validate(StringContract, :length_test, data)
    end

    test "rejects bounded string too short" do
      data = %{short: "abc", long: "test", bounded: "hi"}
      assert {:error, violations} = Validator.validate(StringContract, :length_test, data)

      assert [%{field: :bounded, error: error}] = violations
      assert error =~ "minimum length"
    end

    test "rejects bounded string too long" do
      data = %{short: "abc", long: "test", bounded: "this is too long"}
      assert {:error, violations} = Validator.validate(StringContract, :length_test, data)

      assert [%{field: :bounded, error: error}] = violations
      assert error =~ "maximum length"
    end
  end

  describe "number constraints" do
    defmodule NumberContract do
      use Perimeter.Contract

      defcontract :integer_range do
        required(:age, :integer, min: 0, max: 150)
      end

      defmodule FloatContract do
        use Perimeter.Contract

        defcontract :float_range do
          required(:temperature, :float, min: -273.15, max: 1000.0)
        end
      end
    end

    test "validates integer min" do
      data = %{age: 25}
      assert {:ok, _} = Validator.validate(NumberContract, :integer_range, data)
    end

    test "rejects integer below min" do
      data = %{age: -1}
      assert {:error, violations} = Validator.validate(NumberContract, :integer_range, data)

      assert [%{field: :age, error: error}] = violations
      assert error =~ "minimum value"
    end

    test "validates integer max" do
      data = %{age: 150}
      assert {:ok, _} = Validator.validate(NumberContract, :integer_range, data)
    end

    test "rejects integer above max" do
      data = %{age: 200}
      assert {:error, violations} = Validator.validate(NumberContract, :integer_range, data)

      assert [%{field: :age, error: error}] = violations
      assert error =~ "maximum value"
    end

    test "validates float min" do
      data = %{temperature: 0.0}
      assert {:ok, _} = Validator.validate(NumberContract.FloatContract, :float_range, data)
    end

    test "rejects float below min" do
      data = %{temperature: -300.0}

      assert {:error, violations} =
               Validator.validate(NumberContract.FloatContract, :float_range, data)

      assert [%{field: :temperature, error: error}] = violations
      assert error =~ "minimum value"
    end
  end

  describe "enum constraints" do
    defmodule EnumContract do
      use Perimeter.Contract

      defcontract :user do
        required(:role, :atom, in: [:admin, :user, :guest])
        required(:status, :string, in: ["active", "inactive", "pending"])
      end
    end

    test "validates atom in list" do
      data = %{role: :admin, status: "active"}
      assert {:ok, _} = Validator.validate(EnumContract, :user, data)
    end

    test "rejects atom not in list" do
      data = %{role: :superadmin, status: "active"}
      assert {:error, violations} = Validator.validate(EnumContract, :user, data)

      assert [%{field: :role, error: error}] = violations
      assert error =~ "must be one of"
    end

    test "validates string in list" do
      data = %{role: :user, status: "pending"}
      assert {:ok, _} = Validator.validate(EnumContract, :user, data)
    end

    test "rejects string not in list" do
      data = %{role: :user, status: "archived"}
      assert {:error, violations} = Validator.validate(EnumContract, :user, data)

      assert [%{field: :status, error: error}] = violations
      assert error =~ "must be one of"
    end
  end

  describe "nested map validation" do
    defmodule NestedContract do
      use Perimeter.Contract

      defcontract :user do
        required(:email, :string)

        optional :address, :map do
          required(:city, :string)
          required(:zip, :string, format: ~r/^\d{5}$/)
          optional(:state, :string)
        end
      end
    end

    test "validates nested map with all fields" do
      data = %{
        email: "test@example.com",
        address: %{
          city: "Portland",
          zip: "97201",
          state: "OR"
        }
      }

      assert {:ok, _} = Validator.validate(NestedContract, :user, data)
    end

    test "validates nested map without optional fields" do
      data = %{
        email: "test@example.com",
        address: %{
          city: "Portland",
          zip: "97201"
        }
      }

      assert {:ok, _} = Validator.validate(NestedContract, :user, data)
    end

    test "validates when optional nested map is missing" do
      data = %{email: "test@example.com"}
      assert {:ok, _} = Validator.validate(NestedContract, :user, data)
    end

    test "rejects nested field type violation" do
      data = %{
        email: "test@example.com",
        address: %{
          city: 123,
          zip: "97201"
        }
      }

      assert {:error, violations} = Validator.validate(NestedContract, :user, data)
      assert [%{field: :city, path: [:address], error: error}] = violations
      assert error =~ "expected string"
    end

    test "rejects nested field constraint violation" do
      data = %{
        email: "test@example.com",
        address: %{
          city: "Portland",
          zip: "invalid"
        }
      }

      assert {:error, violations} = Validator.validate(NestedContract, :user, data)
      assert [%{field: :zip, path: [:address], error: error}] = violations
      assert error =~ "does not match format"
    end

    test "rejects missing required nested field" do
      data = %{
        email: "test@example.com",
        address: %{
          zip: "97201"
        }
      }

      assert {:error, violations} = Validator.validate(NestedContract, :user, data)
      assert [%{field: :city, path: [:address], error: "is required"}] = violations
    end

    test "rejects nested map with wrong type for parent" do
      data = %{
        email: "test@example.com",
        address: "not a map"
      }

      assert {:error, violations} = Validator.validate(NestedContract, :user, data)
      assert [%{field: :address, error: error}] = violations
      assert error =~ "expected map"
    end
  end

  describe "deeply nested validation" do
    defmodule DeepNestedContract do
      use Perimeter.Contract

      defcontract :user do
        optional :profile, :map do
          optional :settings, :map do
            required(:theme, :string)
            required(:notifications, :boolean)
          end
        end
      end
    end

    test "validates deeply nested structure" do
      data = %{
        profile: %{
          settings: %{
            theme: "dark",
            notifications: true
          }
        }
      }

      assert {:ok, _} = Validator.validate(DeepNestedContract, :user, data)
    end

    test "reports violations with full path" do
      data = %{
        profile: %{
          settings: %{
            theme: 123,
            notifications: true
          }
        }
      }

      assert {:error, violations} = Validator.validate(DeepNestedContract, :user, data)
      assert [%{field: :theme, path: [:profile, :settings], error: error}] = violations
      assert error =~ "expected string"
    end
  end

  describe "list validation" do
    defmodule ListContract do
      use Perimeter.Contract

      defcontract :data do
        required(:tags, {:list, :string})
        required(:counts, {:list, :integer})
        optional(:flags, {:list, :boolean})
      end
    end

    test "validates list of correct type" do
      data = %{
        tags: ["a", "b", "c"],
        counts: [1, 2, 3]
      }

      assert {:ok, _} = Validator.validate(ListContract, :data, data)
    end

    test "validates empty list" do
      data = %{
        tags: [],
        counts: []
      }

      assert {:ok, _} = Validator.validate(ListContract, :data, data)
    end

    test "rejects list with wrong item type" do
      data = %{
        tags: ["a", 123, "c"],
        counts: [1, 2, 3]
      }

      assert {:error, violations} = Validator.validate(ListContract, :data, data)
      assert [%{field: :tags, error: error}] = violations
      assert error =~ "invalid list item"
    end

    test "rejects non-list for list field" do
      data = %{
        tags: "not a list",
        counts: [1, 2, 3]
      }

      assert {:error, violations} = Validator.validate(ListContract, :data, data)
      assert [%{field: :tags, error: error}] = violations
      assert error =~ "expected list"
    end

    test "validates optional list when present" do
      data = %{
        tags: ["a"],
        counts: [1],
        flags: [true, false]
      }

      assert {:ok, _} = Validator.validate(ListContract, :data, data)
    end

    test "rejects optional list with wrong item type" do
      data = %{
        tags: ["a"],
        counts: [1],
        flags: [true, "not boolean"]
      }

      assert {:error, violations} = Validator.validate(ListContract, :data, data)
      assert [%{field: :flags, error: error}] = violations
      assert error =~ "invalid list item"
    end
  end

  describe "untyped list validation" do
    defmodule UntypedListContract do
      use Perimeter.Contract

      defcontract :data do
        required(:items, :list)
      end
    end

    test "validates any list" do
      data = %{items: [1, "two", :three, %{four: 4}]}
      assert {:ok, _} = Validator.validate(UntypedListContract, :data, data)
    end

    test "rejects non-list" do
      data = %{items: "not a list"}
      assert {:error, violations} = Validator.validate(UntypedListContract, :data, data)
      assert [%{field: :items, error: error}] = violations
      assert error =~ "expected list"
    end
  end

  describe "extra fields" do
    defmodule StrictContract do
      use Perimeter.Contract

      defcontract :user do
        required(:email, :string)
      end
    end

    test "allows extra fields by default" do
      data = %{email: "test@example.com", extra: "field"}
      assert {:ok, validated} = Validator.validate(StrictContract, :user, data)
      assert validated.email == "test@example.com"
      assert validated.extra == "field"
    end
  end
end
