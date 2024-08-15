# frozen_string_literal: true

# A sample Guardfile
# More info at https://github.com/guard/guard#readme

## Uncomment and set this to only include directories you want to watch
# directories %w(app lib config test spec features) \
#  .select{|d| Dir.exist?(d) ? d : UI.warning("Directory #{d} does not exist")}

## Note: if you are using the `directories` clause above and you are not
## watching the project directory ('.'), then you will want to move
## the Guardfile to a watched dir and symlink it back, e.g.
#
#  $ mkdir config
#  $ mv Guardfile config/
#  $ ln -s config/Guardfile .
#
# and, you'll have to watch "config/Guardfile" instead of "Guardfile"

# This group allows to skip running RuboCop when RSpec failed.
group :red_green_refactor, halt_on_fail: true do
  guard :rspec, cmd: 'bundle exec rspec' do
    require 'guard/rspec/dsl'
    dsl = Guard::RSpec::Dsl.new(self)

    # # RSpec files
    rspec = dsl.rspec
    watch(rspec.spec_helper) { rspec.spec_dir }
    watch(rspec.spec_support) { rspec.spec_dir }
    watch(rspec.spec_files)

    # TODO: move specs to spec/lib to be standard
    watch(%r{^lib/(.+)\.rb$}) { |m| "spec/#{m[1]}_spec.rb" }
  end

  guard :rubocop, all_on_start: false,
                  cli: ['--format', 'progress'] do
    watch(/.+\.rb$/)
    watch('Gemfile')
    watch(%r{(?:.+/)?\.rubocop(?:_todo)?\.yml$}) { |m| File.dirname(m[0]) }
  end

  guard 'reek', all_on_start: false, run_all: false, cli: '--single-line --no-wiki-links' do
    watch(/.+\.rb$/)
    watch('.reek')
  end
end
