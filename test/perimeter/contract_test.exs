defmodule Perimeter.ContractTest do
  use ExUnit.Case, async: true
  doctest Perimeter.Contract

  describe "defcontract/2 - basic contract structure" do
    test "defines a contract with required fields" do
      defmodule TestContract1 do
        use Perimeter.Contract

        defcontract :user do
          required(:name, :string)
          required(:age, :integer)
        end
      end

      contract = TestContract1.__contract__(:user)
      assert contract.name == :user
      assert length(contract.fields) == 2

      name_field = Enum.find(contract.fields, &(&1.name == :name))
      assert name_field.name == :name
      assert name_field.type == :string
      assert name_field.required == true

      age_field = Enum.find(contract.fields, &(&1.name == :age))
      assert age_field.name == :age
      assert age_field.type == :integer
      assert age_field.required == true
    end

    test "returns nil for undefined contract" do
      defmodule TestContract2 do
        use Perimeter.Contract

        defcontract :user do
          required(:name, :string)
        end
      end

      assert TestContract2.__contract__(:nonexistent) == nil
    end

    test "supports multiple contracts in one module" do
      defmodule TestContract3 do
        use Perimeter.Contract

        defcontract :user do
          required(:email, :string)
        end

        defcontract :post do
          required(:title, :string)
        end
      end

      user_contract = TestContract3.__contract__(:user)
      post_contract = TestContract3.__contract__(:post)

      assert user_contract.name == :user
      assert post_contract.name == :post
      assert length(user_contract.fields) == 1
      assert length(post_contract.fields) == 1
    end
  end

  describe "optional/3 - optional fields" do
    test "supports optional fields" do
      defmodule TestContract4 do
        use Perimeter.Contract

        defcontract :user do
          required(:email, :string)
          optional(:bio, :string)
        end
      end

      contract = TestContract4.__contract__(:user)
      required_field = Enum.find(contract.fields, &(&1.name == :email))
      optional_field = Enum.find(contract.fields, &(&1.name == :bio))

      assert required_field.required == true
      assert optional_field.required == false
    end

    test "supports mix of required and optional fields" do
      defmodule TestContract5 do
        use Perimeter.Contract

        defcontract :user do
          required(:email, :string)
          required(:password, :string)
          optional(:name, :string)
          optional(:bio, :string)
        end
      end

      contract = TestContract5.__contract__(:user)
      assert length(contract.fields) == 4

      required_fields = Enum.filter(contract.fields, & &1.required)
      optional_fields = Enum.filter(contract.fields, &(not &1.required))

      assert length(required_fields) == 2
      assert length(optional_fields) == 2
    end
  end

  describe "field constraints" do
    test "supports format constraint" do
      defmodule TestContract6 do
        use Perimeter.Contract

        defcontract :user do
          required(:email, :string, format: ~r/@/)
        end
      end

      contract = TestContract6.__contract__(:user)
      email_field = Enum.find(contract.fields, &(&1.name == :email))

      format_regex = email_field.constraints[:format]
      assert %Regex{} = format_regex
      assert Regex.source(format_regex) == "@"
    end

    test "supports min and max constraints" do
      defmodule TestContract7 do
        use Perimeter.Contract

        defcontract :user do
          required(:age, :integer, min: 0, max: 150)
          required(:password, :string, min_length: 8, max_length: 100)
        end
      end

      contract = TestContract7.__contract__(:user)
      age_field = Enum.find(contract.fields, &(&1.name == :age))
      password_field = Enum.find(contract.fields, &(&1.name == :password))

      assert age_field.constraints[:min] == 0
      assert age_field.constraints[:max] == 150
      assert password_field.constraints[:min_length] == 8
      assert password_field.constraints[:max_length] == 100
    end

    test "supports in constraint for enums" do
      defmodule TestContract8 do
        use Perimeter.Contract

        defcontract :user do
          required(:role, :atom, in: [:admin, :user, :guest])
        end
      end

      contract = TestContract8.__contract__(:user)
      role_field = Enum.find(contract.fields, &(&1.name == :role))

      assert role_field.constraints[:in] == [:admin, :user, :guest]
    end

    test "supports multiple constraints on same field" do
      defmodule TestContract9 do
        use Perimeter.Contract

        defcontract :user do
          required(:username, :string, format: ~r/^[a-z]+$/, min_length: 3, max_length: 20)
        end
      end

      contract = TestContract9.__contract__(:user)
      username_field = Enum.find(contract.fields, &(&1.name == :username))

      format_regex = username_field.constraints[:format]
      assert %Regex{} = format_regex
      assert Regex.source(format_regex) == "^[a-z]+$"
      assert username_field.constraints[:min_length] == 3
      assert username_field.constraints[:max_length] == 20
    end
  end

  describe "nested contracts" do
    test "supports nested field definitions" do
      defmodule TestContract10 do
        use Perimeter.Contract

        defcontract :user do
          required(:email, :string)

          optional :address, :map do
            required(:street, :string)
            required(:city, :string)
          end
        end
      end

      contract = TestContract10.__contract__(:user)
      address_field = Enum.find(contract.fields, &(&1.name == :address))

      assert address_field.type == :map
      assert is_list(address_field.nested_fields)
      assert length(address_field.nested_fields) == 2

      street_field = Enum.find(address_field.nested_fields, &(&1.name == :street))
      city_field = Enum.find(address_field.nested_fields, &(&1.name == :city))

      assert street_field.required == true
      assert city_field.required == true
    end

    test "supports nested fields with constraints" do
      defmodule TestContract11 do
        use Perimeter.Contract

        defcontract :user do
          optional :address, :map do
            required(:zip, :string, format: ~r/^\d{5}$/)
          end
        end
      end

      contract = TestContract11.__contract__(:user)
      address_field = Enum.find(contract.fields, &(&1.name == :address))
      zip_field = Enum.find(address_field.nested_fields, &(&1.name == :zip))

      format_regex = zip_field.constraints[:format]
      assert %Regex{} = format_regex
      assert Regex.source(format_regex) == "^\\d{5}$"
    end

    test "supports deeply nested fields" do
      defmodule TestContract12 do
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

      contract = TestContract12.__contract__(:user)
      profile_field = Enum.find(contract.fields, &(&1.name == :profile))
      settings_field = Enum.find(profile_field.nested_fields, &(&1.name == :settings))

      assert is_list(settings_field.nested_fields)
      assert length(settings_field.nested_fields) == 2
    end

    test "supports optional nested fields" do
      defmodule TestContract13 do
        use Perimeter.Contract

        defcontract :user do
          optional :address, :map do
            required(:city, :string)
            optional(:state, :string)
          end
        end
      end

      contract = TestContract13.__contract__(:user)
      address_field = Enum.find(contract.fields, &(&1.name == :address))

      city_field = Enum.find(address_field.nested_fields, &(&1.name == :city))
      state_field = Enum.find(address_field.nested_fields, &(&1.name == :state))

      assert city_field.required == true
      assert state_field.required == false
    end
  end

  describe "list types" do
    test "supports list of basic types" do
      defmodule TestContract14 do
        use Perimeter.Contract

        defcontract :data do
          required(:tags, {:list, :string})
          required(:counts, {:list, :integer})
        end
      end

      contract = TestContract14.__contract__(:data)
      tags_field = Enum.find(contract.fields, &(&1.name == :tags))
      counts_field = Enum.find(contract.fields, &(&1.name == :counts))

      assert tags_field.type == {:list, :string}
      assert counts_field.type == {:list, :integer}
    end

    test "supports optional lists" do
      defmodule TestContract15 do
        use Perimeter.Contract

        defcontract :data do
          optional(:tags, {:list, :string})
        end
      end

      contract = TestContract15.__contract__(:data)
      tags_field = Enum.find(contract.fields, &(&1.name == :tags))

      assert tags_field.required == false
      assert tags_field.type == {:list, :string}
    end
  end

  describe "all supported types" do
    test "supports all basic types" do
      defmodule TestContract16 do
        use Perimeter.Contract

        defcontract :all_types do
          required(:string_field, :string)
          required(:integer_field, :integer)
          required(:float_field, :float)
          required(:boolean_field, :boolean)
          required(:atom_field, :atom)
          required(:map_field, :map)
          required(:list_field, :list)
        end
      end

      contract = TestContract16.__contract__(:all_types)
      assert length(contract.fields) == 7

      types = Enum.map(contract.fields, & &1.type)
      assert :string in types
      assert :integer in types
      assert :float in types
      assert :boolean in types
      assert :atom in types
      assert :map in types
      assert :list in types
    end
  end
end
