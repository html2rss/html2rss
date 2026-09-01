# frozen_string_literal: true

RSpec.describe Html2rss::Test::EnhanceAudit do
  let(:fixture_dir) { File.expand_path('../../../fixtures/enhance_audit', __dir__) }
  let(:time_zone) { 'UTC' }

  def response_for(fixture_name)
    body = File.read(File.join(fixture_dir, fixture_name))
    Html2rss::RequestService::Response.new(
      url: 'https://example.com/list',
      headers: { 'content-type' => 'text/html' },
      body:
    )
  end

  def probe(fixture_name, selectors)
    described_class.probe(response: response_for(fixture_name), selectors:, time_zone:)
  end

  describe '.probe' do
    context 'with rich_card.html' do
      let(:selectors) do
        {
          items: { selector: 'article.card', enhance: true },
          title: { selector: 'h2' },
          url: { selector: 'a', extractor: 'href' }
        }
      end

      it 'counts description gains without junk warnings', :aggregate_failures do
        slice = probe('rich_card.html', selectors)

        expect(slice.enhance_gains.descriptions_added).to be >= 1
        expect(slice.enhance_gains.no_op).to be(false)
        expect(slice.warnings).not_to include(:enhance_category_only_description)
        expect(slice.warnings).not_to include(:enhance_image_only_description)
      end
    end

    context 'with anchor_item.html' do
      let(:selectors) do
        {
          items: { selector: 'div.item', enhance: true },
          title: { selector: 'h3' },
          url: { selector: 'a', extractor: 'href' }
        }
      end

      it 'warns when enhance adds category or image-only descriptions', :aggregate_failures do
        slice = probe('anchor_item.html', selectors)

        expect(slice.enhance_gains.descriptions_added).to be_positive
        expect(slice.warnings).to include(:enhance_category_only_description, :enhance_image_only_description)
      end
    end

    context 'with no_op.html' do
      let(:selectors) do
        {
          items: { selector: 'div.item', enhance: true },
          title: { selector: '.title' },
          url: { selector: '.url', extractor: 'href' },
          description: { selector: '.desc' }
        }
      end

      it 'reports enhance_no_op when selectors already fill all fields', :aggregate_failures do
        slice = probe('no_op.html', selectors)

        expect(slice.enhance_gains.no_op).to be(true)
        expect(slice.warnings).to include(:enhance_no_op)
      end
    end

    context 'with mixed_listing.html' do
      let(:selectors) do
        {
          items: { selector: 'article.card', enhance: true },
          title: { selector: 'h2' },
          url: { selector: 'a', extractor: 'href' }
        }
      end

      it 'omits enhance_no_op when any item gains curator fields', :aggregate_failures do
        slice = probe('mixed_listing.html', selectors)

        expect(slice.enhance_gains.no_op).to be(false)
        expect(slice.enhance_gains.descriptions_added).to be >= 1
        expect(slice.warnings).not_to include(:enhance_no_op)
      end
    end
  end
end
