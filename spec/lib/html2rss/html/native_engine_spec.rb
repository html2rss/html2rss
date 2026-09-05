# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Html::NativeEngine do
  describe '.load!' do
    it 'loads the compiled extension or raises a clear LoadError' do
      begin
        described_class.load!
      rescue LoadError => e
        expect(e.message).to match(/rake compile/)
        skip 'html2rss_parser not compiled'
      end

      expect(described_class).to be_available
      expect(Html2rss::Html.const_defined?(:NativeEngine)).to be(true)
    end
  end
end
