# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Registry::BundleRelativePath do
  describe '.validate_config_path!' do
    it 'accepts normal config paths' do
      expect(described_class.validate_config_path!('configs/example.com/feed.yml'))
        .to eq('configs/example.com/feed.yml')
    end

    [
      ['configs/../evil.yml', /Path traversal/],
      ['etc/passwd', /Invalid file path/],
      ['/configs/abs.yml', /Invalid file path/]
    ].each do |path, message|
      it "rejects #{path.inspect}" do
        expect { described_class.validate_config_path!(path) }
          .to raise_error(Html2rss::Registry::ManifestError, message)
      end
    end
  end

  describe '.validate_archive_entry!' do
    [
      ['../escape.yml', /Path traversal/],
      ['/abs.yml', /Absolute path/]
    ].each do |path, message|
      it "rejects #{path.inspect}" do
        expect { described_class.validate_archive_entry!(path) }
          .to raise_error(Html2rss::Registry::ArchiveError, message)
      end
    end
  end

  describe '.resolve_config!' do
    it 'resolves paths under configs/' do
      bundle_dir = RegistryTestSupport::VALID_BUNDLE
      absolute = described_class.resolve_config!(bundle_dir, 'configs/anthropic.com/news.yml')
      expect(absolute).to eq(File.expand_path('configs/anthropic.com/news.yml', bundle_dir))
    end
  end
end
