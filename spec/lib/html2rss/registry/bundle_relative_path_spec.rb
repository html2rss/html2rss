# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe Html2rss::Registry::BundleRelativePath do
  let(:bundle_dir) { RegistryTestSupport::VALID_BUNDLE }

  describe '.validate_config_path!' do
    it 'accepts normal config paths' do
      expect(described_class.validate_config_path!('configs/example.com/feed.yml'))
        .to eq('configs/example.com/feed.yml')
    end

    it 'rejects traversal segments' do
      expect do
        described_class.validate_config_path!('configs/../evil.yml')
      end.to raise_error(Html2rss::Registry::ManifestError, /Path traversal/)
    end
  end

  describe '.resolve_config!' do
    it 'resolves paths under configs/' do
      absolute = described_class.resolve_config!(bundle_dir, 'configs/anthropic.com/news.yml')
      expect(absolute).to eq(File.expand_path('configs/anthropic.com/news.yml', bundle_dir))
    end

    it 'rejects paths that escape configs/ after normalization' do
      expect do
        described_class.resolve_config!(bundle_dir, 'configs/foo/../../outside.yml')
      end.to raise_error(Html2rss::Registry::ManifestError, /Path traversal/)
    end
  end
end
