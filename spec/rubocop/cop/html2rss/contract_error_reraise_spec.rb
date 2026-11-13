# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength -- offense/allowed fixtures are heredocs

require 'rubocop'
require 'rubocop/rspec/support'
require_relative '../../../../.rubocop/cops/html2rss/contract_error_reraise'

RSpec.describe RuboCop::Cop::Html2rss::ContractErrorReraise, :config do
  include RuboCop::RSpec::ExpectOffense

  let(:message) do
    'Re-raise Html2rss::ContractError first: add `rescue Html2rss::ContractError` + `raise` before this clause.'
  end

  context 'when a broad rescue has no ContractError guard' do
    it 'registers an offense for Html2rss::Error' do
      expect_offense(<<~RUBY)
        begin
          work
        rescue Html2rss::Error => error
        ^^^^^^ #{message}
          log(error)
        end
      RUBY
    end

    it 'registers an offense for ::Html2rss::Error and an Error list entry' do
      expect_offense(<<~RUBY)
        begin
          work
        rescue ::Html2rss::Error
        ^^^^^^ #{message}
          nil
        rescue KeyError, Html2rss::Error
        ^^^^^^ #{message}
          nil
        end
      RUBY
    end

    it 'registers an offense for unqualified Error, even outside module Html2rss' do
      expect_offense(<<~RUBY)
        begin
          work
        rescue Error
        ^^^^^^ #{message}
          nil
        end
      RUBY
    end

    it 'registers an offense for StandardError, Exception, ::StandardError and Object::Exception' do
      expect_offense(<<~RUBY)
        begin
          work
        rescue StandardError
        ^^^^^^ #{message}
          nil
        rescue ::StandardError
        ^^^^^^ #{message}
          nil
        rescue Object::Exception
        ^^^^^^ #{message}
          nil
        end
      RUBY
    end

    it 'registers an offense for bare rescue, rescue => e and the rescue modifier' do
      expect_offense(<<~RUBY)
        begin
          work
        rescue
        ^^^^^^ #{message}
          nil
        end
        begin
          work
        rescue => error
        ^^^^^^ #{message}
          log(error)
        end
        value = work rescue nil
                     ^^^^^^ #{message}
      RUBY
    end

    it 'registers an offense in a def and a block body' do
      expect_offense(<<~RUBY)
        def call
          work
        rescue Html2rss::Error
        ^^^^^^ #{message}
          nil
        end
        items.each do |item|
          work(item)
        rescue Html2rss::Error
        ^^^^^^ #{message}
          nil
        end
      RUBY
    end

    it 'registers an offense when the guard comes after the broad clause' do
      expect_offense(<<~RUBY)
        begin
          work
        rescue Html2rss::Error
        ^^^^^^ #{message}
          nil
        rescue Html2rss::ContractError
          raise
        end
      RUBY
    end

    it 'registers an offense when the ContractError clause does not re-raise' do
      expect_offense(<<~RUBY)
        begin
          work
        rescue Html2rss::ContractError
          log
        rescue Html2rss::Error
        ^^^^^^ #{message}
          nil
        end
      RUBY
    end

    it 'registers an offense when only a conditional raise guards' do
      expect_offense(<<~RUBY)
        begin
          work
        rescue Html2rss::ContractError => error
          raise error if strict?
        rescue Html2rss::Error
        ^^^^^^ #{message}
          nil
        end
      RUBY
    end

    it 'registers an offense when the guard re-raises another variable' do
      expect_offense(<<~RUBY)
        begin
          work
        rescue Html2rss::ContractError => error
          raise other
        rescue Html2rss::Error
        ^^^^^^ #{message}
          nil
        end
      RUBY
    end

    it 'registers an offense for an empty clause body' do
      expect_offense(<<~RUBY)
        begin
          work
        rescue Html2rss::Error
        ^^^^^^ #{message}
        end
      RUBY
    end

    it 'registers an offense when an earlier re-raising clause names only narrow classes' do
      expect_offense(<<~RUBY)
        begin
          work
        rescue KeyError
          raise
        rescue Html2rss::Error
        ^^^^^^ #{message}
          nil
        end
      RUBY
    end

    it 'registers an offense when the re-raised value is not the rescued variable' do
      expect_offense(<<~RUBY)
        begin
          work
        rescue Html2rss::ContractError => error
          other = error.cause
          raise other
        rescue Html2rss::Error
        ^^^^^^ #{message}
          nil
        end
        begin
          work
        rescue Html2rss::ContractError
          raise error
        rescue Html2rss::Error
        ^^^^^^ #{message}
          nil
        end
        begin
          work
        rescue Html2rss::ContractError => error
          raise error, 'wrapped'
        rescue Html2rss::Error
        ^^^^^^ #{message}
          nil
        end
        begin
          work
        rescue Html2rss::ContractError => error
          raise :error
        rescue Html2rss::Error
        ^^^^^^ #{message}
          nil
        end
        begin
          work
        rescue Html2rss::ContractError
          other.raise
        rescue Html2rss::Error
        ^^^^^^ #{message}
          nil
        end
        begin
          work
        rescue Html2rss::ContractError
          raise Html2rss::Error
        rescue Html2rss::Error
        ^^^^^^ #{message}
          nil
        end
      RUBY
    end

    it 'registers an offense when a guard in a different begin does not cover the clause' do
      expect_offense(<<~RUBY)
        begin
          work
        rescue Html2rss::ContractError
          raise
        end
        begin
          work
        rescue Html2rss::Error
        ^^^^^^ #{message}
          nil
        end
      RUBY
    end
  end

  context 'when an earlier clause re-raises ContractError' do
    it 'allows bare raise, qualified and unqualified spellings' do
      expect_no_offenses(<<~RUBY)
        begin
          work
        rescue Html2rss::ContractError
          raise
        rescue Html2rss::Error => error
          log(error)
        end
        begin
          work
        rescue ::Html2rss::ContractError
          raise
        rescue StandardError
          nil
        end
        begin
          work
        rescue ContractError
          raise
        rescue Error
          nil
        end
      RUBY
    end

    it 'allows raise of the rescued variable and a trailing re-raise after other statements' do
      expect_no_offenses(<<~RUBY)
        begin
          work
        rescue Html2rss::ContractError => error
          raise error
        rescue Html2rss::Error
          nil
        end
        begin
          work
        rescue Html2rss::ContractError
          log
          raise
        rescue Exception
          nil
        end
      RUBY
    end

    it 'allows a ContractError list entry beside a sibling that re-raises' do
      expect_no_offenses(<<~RUBY)
        begin
          work
        rescue KeyError, Html2rss::ContractError
          raise
        rescue Html2rss::Error
          nil
        end
      RUBY
    end

    it 'guards every later broad clause, not only the next' do
      expect_no_offenses(<<~RUBY)
        begin
          work
        rescue Html2rss::ContractError
          raise
        rescue KeyError
          nil
        rescue Html2rss::Error
          nil
        rescue StandardError
          nil
        end
      RUBY
    end
  end

  context 'when the clause cannot swallow a ContractError' do
    it 'allows a broad clause that itself re-raises' do
      expect_no_offenses(<<~RUBY)
        begin
          work
        rescue Html2rss::Error => error
          raise error
        end
        begin
          work
        rescue StandardError
          cleanup
          raise
        end
      RUBY
    end

    it 'allows narrow classes, ContractError alone, other-namespace Error and splat lists' do
      expect_no_offenses(<<~RUBY)
        begin
          work
        rescue Html2rss::Url::InvalidUrlError, ArgumentError
          nil
        rescue Html2rss::ContractError
          nil
        rescue Zlib::Error, RSS::Error, Foo::StandardError, Other::Html2rss::Error
          nil
        rescue self::Error, namespace::StandardError, build(1)::Error
          nil
        rescue *OPERATIONAL_ERRORS
          nil
        end
      RUBY
    end

    it 'allows a begin without rescue' do
      expect_no_offenses(<<~RUBY)
        begin
          work
        ensure
          cleanup
        end
      RUBY
    end
  end

  context 'when the ContractError clause can leave early' do
    it 'registers an offense for a conditional return before the raise' do
      expect_offense(<<~RUBY)
        def run
          work
        rescue Html2rss::ContractError => error
          return nil if error.message.empty?
          raise
        rescue Html2rss::Error
        ^^^^^^ #{message}
          nil
        end
      RUBY
    end

    it 'registers an offense for next or break before the raise' do
      expect_offense(<<~RUBY)
        items.each do |item|
          work(item)
        rescue Html2rss::ContractError
          next if skip?
          raise
        rescue Html2rss::Error
        ^^^^^^ #{message}
          nil
        end
        loop do
          work
        rescue Html2rss::ContractError
          break if done?
          raise
        rescue StandardError
        ^^^^^^ #{message}
          nil
        end
      RUBY
    end

    it 'registers an offense for a return nested in a plain block of the clause' do
      expect_offense(<<~RUBY)
        def run
          work
        rescue Html2rss::ContractError => error
          handlers.each { |handler| return handler if handler.match?(error) }
          raise
        rescue Html2rss::Error
        ^^^^^^ #{message}
          nil
        end
      RUBY
    end

    it 'allows next and break that only leave a block or loop inside the clause' do
      expect_no_offenses(<<~RUBY)
        begin
          work
        rescue Html2rss::ContractError => error
          details.each { |detail| next if detail.nil? }
          while pending? do break end
          raise error
        rescue Html2rss::Error
          nil
        end
      RUBY
    end
  end
end

# rubocop:enable RSpec/ExampleLength
