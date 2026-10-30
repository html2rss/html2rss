# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Config::RequestControls do
  describe '.from_config' do
    let(:symbol_config) { { strategy: :botasaurus, request: { max_redirects: 3, max_requests: 9 } } }

    it 'extracts explicit controls from symbol-keyed config', :aggregate_failures do
      controls = described_class.from_config(symbol_config)

      expect(controls).to have_attributes(strategy: :botasaurus, max_redirects: 3, max_requests: 9)
      explicit_keys = %i[strategy max_redirects max_requests].select { controls.explicit?(_1) }
      expect(explicit_keys).to eq(%i[strategy max_redirects max_requests])
    end

    it 'treats absent keys as implicit and a present nil as explicit', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      absent = described_class.from_config({})
      nil_valued = described_class.from_config(strategy: nil, request: { max_requests: nil })

      expect(absent.explicit?(:strategy)).to be(false)
      expect(absent.explicit?(:max_requests)).to be(false)
      expect(nil_valued).to have_attributes(strategy: nil, max_requests: nil)
      expect(nil_valued.explicit?(:strategy)).to be(true)
      expect(nil_valued.explicit?(:max_requests)).to be(true)
    end

    it 'ignores a non-hash request envelope', :aggregate_failures do
      controls = described_class.from_config(request: 'invalid')

      expect(controls).to have_attributes(max_requests: nil, max_redirects: nil)
      expect(controls.explicit?(:max_requests)).to be(false)
    end

    it 'raises when top-level keys are not symbols' do
      expect do
        described_class.from_config('strategy' => :botasaurus)
      end.to raise_error(ArgumentError, /config must use symbol keys/)
    end

    it 'raises when request keys are not symbols' do
      expect do
        described_class.from_config(request: { 'max_requests' => 4 })
      end.to raise_error(ArgumentError, /config\[:request\] must use symbol keys/)
    end
  end

  describe '.from_shortcut' do
    it 'marks strategy explicit only when non-default', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      default_name = Html2rss::Config.default_strategy_name
      omitted = described_class.from_shortcut(strategy: default_name, max_requests: 4)
      explicit = described_class.from_shortcut(strategy: :botasaurus, max_redirects: 2)

      expect(omitted.explicit?(:strategy)).to be(false)
      expect(omitted.explicit?(:max_requests)).to be(true)
      expect(explicit.explicit?(:strategy)).to be(true)
      expect(explicit.explicit?(:max_redirects)).to be(true)
    end

    it 'keeps normalized strategy and budget values with their provenance', :aggregate_failures do
      controls = described_class.from_shortcut(strategy: 'botasaurus', max_redirects: 2, max_requests: 4)

      expect(controls).to have_attributes(strategy: :botasaurus, max_redirects: 2, max_requests: 4)
      expect(controls.explicit?(:max_requests)).to be(true)
    end

    it 'treats an omitted strategy and budgets as implicit', :aggregate_failures do
      controls = described_class.from_shortcut(strategy: nil)

      expect(controls.strategy).to be_nil
      expect(controls.explicit?(:strategy)).to be(false)
      expect(controls.explicit?(:max_redirects)).to be(false)
      expect(controls.explicit?(:max_requests)).to be(false)
    end
  end

  describe 'option validation' do
    {
      from_shortcut: { max_requests: 0, max_redirects: -1 },
      from_cli_options: { max_requests: 1.5, max_redirects: '3' }
    }.each do |factory, bad|
      it "#{factory} rejects malformed budgets", :aggregate_failures do
        bad.each do |name, value|
          expect { described_class.public_send(factory, strategy: nil, name => value) }
            .to raise_error(Html2rss::InvalidOption, /#{name}/)
        end
      end

      it "#{factory} rejects an unknown strategy" do
        expect { described_class.public_send(factory, strategy: 'nope') }
          .to raise_error(Html2rss::InvalidOption, /strategy/)
      end
    end

    it 'accepts a zero redirect limit and a one-request budget' do
      expect(described_class.from_shortcut(strategy: nil, max_redirects: 0, max_requests: 1).explicit?(:max_redirects))
        .to be(true)
    end
  end

  describe '.from_cli_options' do
    it 'marks strategy explicit when the CLI option is present', :aggregate_failures do
      controls = described_class.from_cli_options(strategy: 'botasaurus', max_requests: nil)

      expect(controls.strategy).to eq(:botasaurus)
      expect(controls.explicit?(:strategy)).to be(true)
      expect(controls.explicit?(:max_requests)).to be(false)
    end

    it 'treats omitted CLI options as implicit and keeps their values nil', :aggregate_failures do
      controls = described_class.from_cli_options(strategy: nil)

      expect(controls.strategy).to be_nil
      expect(controls.explicit?(:strategy)).to be(false)
      expect(controls.explicit?(:max_redirects)).to be(false)
      expect(controls.explicit?(:max_requests)).to be(false)
    end

    it 'marks provided budgets explicit, including zero redirects', :aggregate_failures do
      controls = described_class.from_cli_options(strategy: nil, max_redirects: 0, max_requests: 2)

      expect(controls).to have_attributes(max_redirects: 0, max_requests: 2)
      expect(controls.explicit?(:max_redirects)).to be(true)
      expect(controls.explicit?(:max_requests)).to be(true)
    end
  end

  describe '#apply_to' do
    it 'writes explicit request controls into the nested request config', :aggregate_failures do
      controls = described_class.new(max_requests: 4, explicit_keys: [:max_requests])
      config = {}

      result = controls.apply_to(config)

      expect(result).to equal(config)
      expect(config).to eq(request: { max_requests: 4 })
    end

    it 'writes only explicit controls, including an explicit nil', :aggregate_failures do
      controls = described_class.new(strategy: :botasaurus, max_requests: 4, explicit_keys: [:max_redirects])
      config = {}

      controls.apply_to(config)

      expect(config).to eq(request: { max_redirects: nil })
    end

    it 'merges explicit controls into an existing request hash and writes explicit strategy', :aggregate_failures do
      controls = described_class.new(strategy: :botasaurus, total_timeout_seconds: 9,
                                     explicit_keys: %i[strategy total_timeout_seconds])
      config = { request: { max_redirects: 1 } }

      controls.apply_to(config)

      expect(config).to eq(strategy: :botasaurus, request: { max_redirects: 1, total_timeout_seconds: 9 })
    end

    it 'creates a request hash when the config has none' do
      controls = described_class.new(max_redirects: nil, explicit_keys: [:max_redirects])
      config = {}

      expect(controls.apply_to(config)).to eq(request: { max_redirects: nil })
    end

    it 'raises a clear error when request config is not a hash' do
      controls = described_class.new(max_requests: 4, explicit_keys: [:max_requests])
      config = { request: 'invalid' }

      expect { controls.apply_to(config) }.to raise_error(ArgumentError, 'request config must be a hash')
    end
  end

  describe '#explicit?' do
    it 'accepts string names and de-duplicates explicit keys', :aggregate_failures do
      controls = described_class.new(explicit_keys: %w[max_requests max_requests])

      expect(controls.explicit?('max_requests')).to be(true)
      expect(controls.explicit?(:strategy)).to be(false)
    end
  end

  describe '#with_effective_values' do
    it 'replaces effective values while keeping provenance', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      controls = described_class.new(max_requests: 2, explicit_keys: [:max_requests])

      effective = controls.with_effective_values(strategy: :auto, max_redirects: 5, max_requests: 3,
                                                 total_timeout_seconds: 7)

      expect(effective).to have_attributes(strategy: :auto, max_redirects: 5, max_requests: 3,
                                           total_timeout_seconds: 7)
      expect(effective.explicit?(:max_requests)).to be(true)
      expect(effective.explicit?(:max_redirects)).to be(false)
    end
  end
end
