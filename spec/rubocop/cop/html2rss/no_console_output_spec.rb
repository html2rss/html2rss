# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength -- offense/allowed fixtures are heredocs

require 'rubocop'
require 'rubocop/rspec/support'
require_relative '../../../../.rubocop/cops/html2rss/no_console_output'

RSpec.describe RuboCop::Cop::Html2rss::NoConsoleOutput, :config do
  include RuboCop::RSpec::ExpectOffense

  context 'when a Kernel write method is called' do
    it 'registers an offense for warn' do
      expect_offense(<<~RUBY)
        warn 'careful'
        ^^^^^^^^^^^^^^ Log through Html2rss::Log instead of writing to the console (`warn`).
      RUBY
    end

    it 'registers an offense for Kernel.warn' do
      expect_offense(<<~RUBY)
        Kernel.warn('careful')
        ^^^^^^^^^^^^^^^^^^^^^^ Log through Html2rss::Log instead of writing to the console (`warn`).
      RUBY
    end

    it 'registers an offense for puts, print and p' do
      expect_offense(<<~RUBY)
        def debug(value)
          puts value
          ^^^^^^^^^^ Log through Html2rss::Log instead of writing to the console (`puts`).
          print value
          ^^^^^^^^^^^ Log through Html2rss::Log instead of writing to the console (`print`).
          p value
          ^^^^^^^ Log through Html2rss::Log instead of writing to the console (`p`).
          pp value
          ^^^^^^^^ Log through Html2rss::Log instead of writing to the console (`pp`).
        end
      RUBY
    end

    it 'registers an offense for self.warn and Warning.warn' do
      expect_offense(<<~RUBY)
        self.warn('x')
        ^^^^^^^^^^^^^^ Log through Html2rss::Log instead of writing to the console (`warn`).
        self.puts 'x'
        ^^^^^^^^^^^^^ Log through Html2rss::Log instead of writing to the console (`puts`).
        Warning.warn('x')
        ^^^^^^^^^^^^^^^^^ Log through Html2rss::Log instead of writing to the console (`warn`).
        ::Warning.warn('x')
        ^^^^^^^^^^^^^^^^^^^ Log through Html2rss::Log instead of writing to the console (`warn`).
        Object::Kernel.puts('x')
        ^^^^^^^^^^^^^^^^^^^^^^^^ Log through Html2rss::Log instead of writing to the console (`puts`).
      RUBY
    end

    it 'registers an offense for display on any receiver' do
      expect_offense(<<~RUBY)
        'x'.display
        ^^^^^^^^^^^ Log through Html2rss::Log instead of writing to the console (`display`).
        value.display($stderr)
                      ^^^^^^^ Log through Html2rss::Log instead of writing to the console (`$stderr`).
        ^^^^^^^^^^^^^^^^^^^^^^ Log through Html2rss::Log instead of writing to the console (`display`).
        display
        ^^^^^^^ Log through Html2rss::Log instead of writing to the console (`display`).
      RUBY
    end
  end

  context 'when a standard stream is referenced' do
    it 'registers an offense for $stderr' do
      expect_offense(<<~RUBY)
        $stderr.puts 'careful'
        ^^^^^^^ Log through Html2rss::Log instead of writing to the console (`$stderr`).
      RUBY
    end

    it 'registers an offense for a stream that is the whole program' do
      expect_offense(<<~RUBY)
        $stderr
        ^^^^^^^ Log through Html2rss::Log instead of writing to the console (`$stderr`).
      RUBY
    end

    it 'registers an offense for $stdout' do
      expect_offense(<<~RUBY)
        $stdout.write('x')
        ^^^^^^^ Log through Html2rss::Log instead of writing to the console (`$stdout`).
      RUBY
    end

    it 'registers an offense for STDERR and ::STDOUT' do
      expect_offense(<<~RUBY)
        STDERR.write('x')
        ^^^^^^ Log through Html2rss::Log instead of writing to the console (`STDERR`).
        ::STDOUT.write('x')
        ^^^^^^^^ Log through Html2rss::Log instead of writing to the console (`STDOUT`).
      RUBY
    end

    it 'registers an offense for $> and $DEFAULT_OUTPUT' do
      expect_offense(<<~RUBY)
        $> << 'x'
        ^^ Log through Html2rss::Log instead of writing to the console (`$>`).
        $DEFAULT_OUTPUT.puts('x')
        ^^^^^^^^^^^^^^^ Log through Html2rss::Log instead of writing to the console (`$DEFAULT_OUTPUT`).
      RUBY
    end

    it 'registers an offense for an Object::-qualified stream' do
      expect_offense(<<~RUBY)
        Object::STDERR.write('x')
        ^^^^^^^^^^^^^^ Log through Html2rss::Log instead of writing to the console (`STDERR`).
        ::Object::STDOUT.method(:puts).call('x')
        ^^^^^^^^^^^^^^^^ Log through Html2rss::Log instead of writing to the console (`STDOUT`).
      RUBY
    end

    it 'registers an offense for a stream that is not the Logger device' do
      expect_offense(<<~RUBY)
        Logger.new('log', $stderr)
                          ^^^^^^^ Log through Html2rss::Log instead of writing to the console (`$stderr`).
        Logger.open($stderr)
                    ^^^^^^^ Log through Html2rss::Log instead of writing to the console (`$stderr`).
        File.new($stdout)
                 ^^^^^^^ Log through Html2rss::Log instead of writing to the console (`$stdout`).
        Foo::Logger.new($stderr)
                        ^^^^^^^ Log through Html2rss::Log instead of writing to the console (`$stderr`).
        write($stderr)
              ^^^^^^^ Log through Html2rss::Log instead of writing to the console (`$stderr`).
        new($stderr)
            ^^^^^^^ Log through Html2rss::Log instead of writing to the console (`$stderr`).
        Logger.new { $stderr }
                     ^^^^^^^ Log through Html2rss::Log instead of writing to the console (`$stderr`).
      RUBY
    end
  end

  context 'when output goes through the logger' do
    it 'allows Html2rss::Log and logger calls' do
      expect_no_offenses(<<~RUBY)
        Log.warn('careful')
        Html2rss::Log.info('fine')
        logger.warn('careful')
      RUBY
    end

    it 'allows a standard stream as the Logger device' do
      expect_no_offenses(<<~RUBY)
        Logger.new($stderr)
        ::Logger.new($stdout)
        Logger.new(STDERR)
      RUBY
    end

    it 'allows warn and write methods on other receivers' do
      expect_no_offenses(<<~RUBY)
        Foo::Warning.warn('x')
        Warning.categories
        Warning[:deprecated]
        logger.puts('x')
        Foo::Object::STDERR
        $stdin.read
        Logger.new($>)
        Object::Logger.new($DEFAULT_OUTPUT)
      RUBY
    end

    it 'allows a log method definition and namespaced stream names' do
      expect_no_offenses(<<~RUBY)
        def warn(message)
          Html2rss.logger.warn(message)
        end
        IO::STDERR
        Foo::Kernel.warn('x')
        $PROGRAM_NAME
        p = 1
      RUBY
    end
  end
end
# rubocop:enable RSpec/ExampleLength
