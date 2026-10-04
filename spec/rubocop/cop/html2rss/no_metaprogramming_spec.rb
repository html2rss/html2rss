# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength -- offense/allowed fixtures are heredocs

require 'rubocop'
require 'rubocop/rspec/support'
require_relative '../../../../.rubocop/cops/html2rss/no_metaprogramming'

RSpec.describe RuboCop::Cop::Html2rss::NoMetaprogramming, :config do
  include RuboCop::RSpec::ExpectOffense

  context 'when public_send is used' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        obj.public_send(:foo)
        ^^^^^^^^^^^^^^^^^^^^^ Avoid metaprogramming in lib/; use an explicit type or call.
      RUBY
    end

    it 'allows a direct call' do
      expect_no_offenses(<<~RUBY)
        obj.foo
      RUBY
    end
  end

  context 'when send is used' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        obj.send(:foo)
        ^^^^^^^^^^^^^^ Avoid metaprogramming in lib/; use an explicit type or call.
      RUBY
    end

    it 'allows a comment that mentions send' do
      expect_no_offenses(<<~RUBY)
        # no send in production code
        obj.foo
      RUBY
    end
  end

  context 'when __send__ is used' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        obj.__send__(:foo)
        ^^^^^^^^^^^^^^^^^^ Avoid metaprogramming in lib/; use an explicit type or call.
      RUBY
    end

    it 'allows a literal method name' do
      expect_no_offenses(<<~RUBY)
        obj.foo
      RUBY
    end
  end

  context 'when define_method is used' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        define_method(:foo) { 1 }
        ^^^^^^^^^^^^^^^^^^^ Avoid metaprogramming in lib/; use an explicit type or call.
      RUBY
    end

    it 'allows a written method definition' do
      expect_no_offenses(<<~RUBY)
        def foo
          1
        end
      RUBY
    end
  end

  context 'when instance_variable_get is used' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        instance_variable_get(:@foo)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Avoid metaprogramming in lib/; use an explicit type or call.
      RUBY
    end

    it 'allows defined? memoization' do
      expect_no_offenses(<<~RUBY)
        @foo = 1 unless defined?(@foo)
        @foo
      RUBY
    end
  end

  context 'when instance_variable_set is used' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        instance_variable_set(:@foo, 1)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Avoid metaprogramming in lib/; use an explicit type or call.
      RUBY
    end

    it 'allows a direct instance variable write' do
      expect_no_offenses(<<~RUBY)
        @foo = 1
      RUBY
    end
  end

  context 'when instance_eval is used' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        obj.instance_eval { foo }
        ^^^^^^^^^^^^^^^^^ Avoid metaprogramming in lib/; use an explicit type or call.
      RUBY
    end

    it 'allows a direct instance method call' do
      expect_no_offenses(<<~RUBY)
        obj.foo
      RUBY
    end
  end

  context 'when class_eval is used' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        Foo.class_eval { def bar; end }
        ^^^^^^^^^^^^^^ Avoid metaprogramming in lib/; use an explicit type or call.
      RUBY
    end

    it 'allows a class body' do
      expect_no_offenses(<<~RUBY)
        class Foo
          def bar; end
        end
      RUBY
    end
  end

  context 'when module_eval is used' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        Foo.module_eval { def bar; end }
        ^^^^^^^^^^^^^^^ Avoid metaprogramming in lib/; use an explicit type or call.
      RUBY
    end

    it 'allows a module body' do
      expect_no_offenses(<<~RUBY)
        module Foo
          def bar; end
        end
      RUBY
    end
  end

  context 'when eval is used' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        eval('1 + 1')
        ^^^^^^^^^^^^^ Avoid metaprogramming in lib/; use an explicit type or call.
      RUBY
    end

    it 'allows a Ruby literal' do
      expect_no_offenses(<<~RUBY)
        1 + 1
      RUBY
    end
  end

  context 'when instance_exec is used' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        obj.instance_exec { foo }
        ^^^^^^^^^^^^^^^^^ Avoid metaprogramming in lib/; use an explicit type or call.
      RUBY
    end

    it 'allows yielding to a given block' do
      expect_no_offenses(<<~RUBY)
        def call(&block)
          yield
        end
      RUBY
    end
  end

  context 'when class_exec is used' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        Foo.class_exec { def bar; end }
        ^^^^^^^^^^^^^^ Avoid metaprogramming in lib/; use an explicit type or call.
      RUBY
    end

    it 'allows opening the class' do
      expect_no_offenses(<<~RUBY)
        class Foo
          def bar; end
        end
      RUBY
    end
  end

  context 'when module_exec is used' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        Foo.module_exec { def bar; end }
        ^^^^^^^^^^^^^^^ Avoid metaprogramming in lib/; use an explicit type or call.
      RUBY
    end

    it 'allows opening the module' do
      expect_no_offenses(<<~RUBY)
        module Foo
          def bar; end
        end
      RUBY
    end
  end

  context 'when const_get is used' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        Object.const_get(:Foo)
        ^^^^^^^^^^^^^^^^^^^^^^ Avoid metaprogramming in lib/; use an explicit type or call.
      RUBY
    end

    it 'allows a constant path' do
      expect_no_offenses(<<~RUBY)
        Foo::Bar
      RUBY
    end
  end

  context 'when const_set is used' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        Object.const_set(:Foo, Class.new)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Avoid metaprogramming in lib/; use an explicit type or call.
      RUBY
    end

    it 'allows a class definition' do
      expect_no_offenses(<<~RUBY)
        class Foo
        end
      RUBY
    end
  end

  context 'when const_defined? is used' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        Object.const_defined?(:Foo)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^ Avoid metaprogramming in lib/; use an explicit type or call.
      RUBY
    end

    it 'allows defined? on a constant' do
      expect_no_offenses(<<~RUBY)
        defined?(Foo)
      RUBY
    end
  end

  context 'when respond_to? is used' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        obj.respond_to?(:foo)
        ^^^^^^^^^^^^^^^^^^^^^ Avoid metaprogramming in lib/; use an explicit type or call.
      RUBY
    end

    it 'allows is_a? and case/when on classes' do
      expect_no_offenses(<<~RUBY)
        obj.is_a?(String)
        case obj
        when Integer
          obj
        end
      RUBY
    end
  end

  context 'when method(:x) is used' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        obj.method(:foo)
        ^^^^^^^^^^^^^^^^ Avoid metaprogramming in lib/; use an explicit type or call.
      RUBY
    end

    it 'allows a receiver.method call with no arguments' do
      expect_no_offenses(<<~RUBY)
        request.method
      RUBY
    end
  end

  context 'when Forwardable is used' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        extend Forwardable
               ^^^^^^^^^^^ Avoid metaprogramming in lib/; use an explicit type or call.
      RUBY
    end

    it 'allows an explicit wrapper method' do
      expect_no_offenses(<<~RUBY)
        def info(...)
          logger.info(...)
        end
      RUBY
    end
  end

  context 'when method_missing is defined' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        def method_missing(name, *args)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Avoid metaprogramming in lib/; use an explicit type or call.
          super
        end
      RUBY
    end

    it 'allows a closed-set lookup' do
      expect_no_offenses(<<~RUBY)
        def self.[](name)
          ALL.fetch(name)
        end
      RUBY
    end
  end

  context 'when respond_to_missing? is defined' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        def respond_to_missing?(name, include_private)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Avoid metaprogramming in lib/; use an explicit type or call.
          false
        end
      RUBY
    end

    it 'allows an explicit predicate' do
      expect_no_offenses(<<~RUBY)
        def known?(name)
          ALL.key?(name)
        end
      RUBY
    end
  end

  context 'when Data.define is given a block' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        Data.define(:name) do
        ^^^^^^^^^^^^^^^^^^ Avoid metaprogramming in lib/; use an explicit type or call.
          def label
            name
          end
        end
      RUBY
    end

    it 'allows Data.define followed by a class reopen' do
      expect_no_offenses(<<~RUBY)
        X = Data.define(:name)
        class X
          def label
            name
          end
        end
      RUBY
    end
  end

  context 'when Struct.new is given a block' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        Struct.new(:name) do
        ^^^^^^^^^^^^^^^^^ Avoid metaprogramming in lib/; use an explicit type or call.
          def label
            name
          end
        end
      RUBY
    end

    it 'allows Struct.new without a block' do
      expect_no_offenses(<<~RUBY)
        Pair = Struct.new(:left, :right)
      RUBY
    end
  end

  it 'allows visibility declarations, block-pass literals, and module_function' do
    expect_no_offenses(<<~RUBY)
      private_constant :ALL
      private_class_method :new
      module_function
      names.map(&:to_sym)
    RUBY
  end
end
# rubocop:enable RSpec/ExampleLength
