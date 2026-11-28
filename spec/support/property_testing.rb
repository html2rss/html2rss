# frozen_string_literal: true

require 'prop_check'

##
# Wiring for examples tagged +:property+.
#
# * +PROP_RUNS+ sets runs per +forall+ (default 100).
# * prop_check draws from an unseeded +Random.new+, so +:property+ examples pin that call to
#   +Random.new(seed)+. The seed is +PROP_SEED+ when set, else RSpec's own seed, and every failure
#   prints it. Replay with +PROP_SEED=<seed> bundle exec rspec <file>+.
module PropertyTesting
  DEFAULT_RUNS = 100

  # @return [Integer] seed shared by every property in this process
  def self.seed
    Integer(ENV.fetch('PROP_SEED') { RSpec.configuration.seed })
  end

  # @return [Integer] runs per +forall+
  def self.runs
    Integer(ENV.fetch('PROP_RUNS', DEFAULT_RUNS))
  end
end

PropCheck::Property.configure { |prop_config| prop_config.n_runs = PropertyTesting.runs }

RSpec.configure do |config|
  config.include PropCheck, :property

  config.before(:example, :property) do
    # Every no-arg Random.new inside a property example shares this one seeded stream.
    seeded = Random.new(PropertyTesting.seed)
    allow(Random).to receive(:new).and_call_original
    allow(Random).to receive(:new).with(no_args).and_return(seeded)
  end

  config.after(:example, :property) do |example|
    if example.exception
      RSpec.configuration.reporter.message("property failed; replay with PROP_SEED=#{PropertyTesting.seed}")
    end
  end
end
