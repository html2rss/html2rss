# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength -- offense/allowed fixtures are heredocs

require 'rubocop'
require 'rubocop/rspec/support'
require_relative '../../../../.rubocop/cops/html2rss/local_error_class'

RSpec.describe RuboCop::Cop::Html2rss::LocalErrorClass, :config do
  include RuboCop::RSpec::ExpectOffense

  context 'when a core error class is raised' do
    it 'registers an offense for raise with a message' do
      expect_offense(<<~RUBY)
        raise ArgumentError, 'bad'
        ^^^^^^^^^^^^^^^^^^^^^^^^^^ Raise or subclass an Html2rss::Error subclass defined next to its owner, not `ArgumentError`.
      RUBY
    end

    it 'registers an offense for fail' do
      expect_offense(<<~RUBY)
        fail TypeError, 'bad'
        ^^^^^^^^^^^^^^^^^^^^^ Raise or subclass an Html2rss::Error subclass defined next to its owner, not `TypeError`.
      RUBY
    end

    it 'registers an offense for a ::-qualified class' do
      expect_offense(<<~RUBY)
        raise ::RuntimeError, 'bad'
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^ Raise or subclass an Html2rss::Error subclass defined next to its owner, not `RuntimeError`.
      RUBY
    end

    it 'registers an offense for an instance built with new' do
      expect_offense(<<~RUBY)
        raise StandardError.new('bad')
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Raise or subclass an Html2rss::Error subclass defined next to its owner, not `StandardError`.
      RUBY
    end

    it 'registers an offense for NotImplementedError in an abstract hook' do
      expect_offense(<<~RUBY)
        def fetch
          raise NotImplementedError
          ^^^^^^^^^^^^^^^^^^^^^^^^^ Raise or subclass an Html2rss::Error subclass defined next to its owner, not `NotImplementedError`.
        end
      RUBY
    end

    it 'registers an offense for Kernel.raise' do
      expect_offense(<<~RUBY)
        Kernel.raise KeyError, 'bad'
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Raise or subclass an Html2rss::Error subclass defined next to its owner, not `KeyError`.
      RUBY
    end

    it 'registers an offense inside a block passed to fetch' do
      expect_offense(<<~RUBY)
        ALL.fetch(name) { raise ArgumentError, "unknown: \#{name}" }
                          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Raise or subclass an Html2rss::Error subclass defined next to its owner, not `ArgumentError`.
      RUBY
    end
  end

  context 'when a bare message is raised' do
    it 'registers an offense for a string literal' do
      expect_offense(<<~RUBY)
        raise 'bad'
        ^^^^^^^^^^^ Raise or subclass an Html2rss::Error subclass defined next to its owner, not `RuntimeError`.
      RUBY
    end

    it 'registers an offense for an interpolated string' do
      expect_offense(<<~RUBY)
        fail "bad \#{value}"
        ^^^^^^^^^^^^^^^^^^^ Raise or subclass an Html2rss::Error subclass defined next to its owner, not `RuntimeError`.
      RUBY
    end
  end

  context 'when a local error is raised or re-raised' do
    it 'allows an owner-local error class' do
      expect_no_offenses(<<~RUBY)
        raise InvalidError, 'bad'
        raise Html2rss::InvalidOption, 'bad'
        raise Url::InvalidUrlError.new('bad')
      RUBY
    end

    it 'allows a namespaced class that shares a core short name' do
      expect_no_offenses(<<~RUBY)
        raise Thor::Error, 'bad'
        raise Foo::ArgumentError, 'bad'
      RUBY
    end

    it 'allows re-raising a rescued error' do
      expect_no_offenses(<<~RUBY)
        begin
          work
        rescue Html2rss::Error => error
          raise error
        rescue IOError
          raise
        end
      RUBY
    end

    it 'allows raise called on another receiver' do
      expect_no_offenses(<<~RUBY)
        promise.raise ArgumentError, 'bad'
      RUBY
    end

    it 'allows rescuing a stdlib error' do
      expect_no_offenses(<<~RUBY)
        def parse(value)
          Integer(value)
        rescue ArgumentError, TypeError
          nil
        end
      RUBY
    end
  end

  context 'when a class subclasses a core error' do
    it 'registers an offense for class < ArgumentError' do
      expect_offense(<<~RUBY)
        module Html2rss
          class UnpublishedRequestError < ArgumentError; end
                                          ^^^^^^^^^^^^^ Raise or subclass an Html2rss::Error subclass defined next to its owner, not `ArgumentError`.
        end
      RUBY
    end

    it 'registers an offense for Class.new(StandardError)' do
      expect_offense(<<~RUBY)
        Boom = Class.new(::StandardError)
               ^^^^^^^^^^^^^^^^^^^^^^^^^^ Raise or subclass an Html2rss::Error subclass defined next to its owner, not `StandardError`.
      RUBY
    end

    it 'registers an offense for an Error named class outside the Html2rss root' do
      expect_offense(<<~RUBY)
        module Html2rss
          module MCP
            class Error < StandardError; end
                          ^^^^^^^^^^^^^ Raise or subclass an Html2rss::Error subclass defined next to its owner, not `StandardError`.
          end
        end
      RUBY
    end

    it 'registers an offense when the root error subclasses another core class' do
      expect_offense(<<~RUBY)
        module Html2rss
          class Error < RuntimeError; end
                        ^^^^^^^^^^^^ Raise or subclass an Html2rss::Error subclass defined next to its owner, not `RuntimeError`.
        end
      RUBY
    end

    it 'allows the Html2rss::Error root' do
      expect_no_offenses(<<~RUBY)
        module Html2rss
          class Error < StandardError; end
        end
        class Html2rss::Error < StandardError; end
      RUBY
    end

    it 'allows subclasses of Html2rss::Error and plain classes' do
      expect_no_offenses(<<~RUBY)
        module Html2rss
          class InvalidOption < Error; end
          Boom = Class.new(Html2rss::Error)
          class Plain; end
          Other = Class.new
        end
      RUBY
    end
  end
end
# rubocop:enable RSpec/ExampleLength
