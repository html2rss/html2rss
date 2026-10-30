# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength, RSpec/NestedGroups, RSpec/MultipleMemoizedHelpers
RSpec.describe Html2rss::Test::EnhanceAudit do
  let(:time_zone) { 'UTC' }

  describe '.probe' do
    context 'with stubbed enhance pairs' do # rubocop:disable RSpec/MultipleMemoizedHelpers -- shared stub wiring
      let(:selectors) { { items: { selector: 'li', enhance: true } } }
      let(:response) { instance_double(Html2rss::RequestService::Response) }
      let(:engine) { instance_double(Html2rss::Selectors) }
      let(:plain_item) { Nokogiri::HTML.fragment('<li>x</li>').children.first }
      let(:pairs) { [] }
      let(:slice) { described_class.probe(response:, selectors:, time_zone:) }

      before do
        allow(Html2rss::Selectors).to receive(:new).and_return(engine)
        allow(engine).to receive(:each_enhance_pair) { |&block| pairs.each { |pair| block.call(*pair) } }
      end

      it 'returns nil without an items selector', :aggregate_failures do
        expect(described_class.probe(response:, selectors: nil, time_zone:)).to be_nil
        expect(described_class.probe(response:, selectors: { items: {} }, time_zone:)).to be_nil
        expect(described_class.probe(response:, selectors: { title: { selector: 'h2' } }, time_zone:)).to be_nil
      end

      it 'builds the selector engine from the response, selectors and time zone' do
        slice

        expect(Html2rss::Selectors).to have_received(:new).with(response, selectors:, time_zone:)
      end

      context 'when no items are enhanced' do
        it 'reports a frozen zeroed no-op slice', :aggregate_failures do
          expect(slice.enhance_gains).to eq(
            described_class::EnhanceGains.new(
              items_probed: 0, descriptions_added: 0, no_op: true,
              keys_added: { title: 0, url: 0, description: 0, published_at: 0, categories: 0, author: 0,
                            image: 0, id: 0, enclosures: 0 }
            )
          )
          expect(slice.warnings).to eq([:enhance_no_op])
          expect([slice.warnings, slice.enhance_gains.keys_added]).to all(be_frozen)
        end
      end

      context 'when items gain tracked and untracked keys' do
        let(:pairs) do
          [
            [{ title: 'a', url: nil }, { title: 'a', url: 'u', description: 'Some prose here', author: 'x', extra: 1 },
             plain_item],
            [{}, { title: 'b', description: 'Another prose line', categories: %w[c], image: nil }, plain_item]
          ]
        end

        it 'counts per-key additions, descriptions and probed items', :aggregate_failures do
          expect(slice.enhance_gains).to have_attributes(
            items_probed: 2, descriptions_added: 2, no_op: false,
            keys_added: { title: 1, url: 1, description: 2, published_at: 0, categories: 1, author: 1,
                          image: 0, id: 0, enclosures: 0 }
          )
          expect(slice.warnings).to eq([])
        end
      end

      context 'when only non-curator keys are added' do
        let(:pairs) { [[{}, { categories: %w[c], author: 'x' }, plain_item]] }

        it 'is a no-op and warns', :aggregate_failures do
          expect(slice.enhance_gains).to have_attributes(items_probed: 1, descriptions_added: 0, no_op: true)
          expect(slice.warnings).to eq([:enhance_no_op])
        end
      end

      context 'when a curator key other than description is added' do
        let(:pairs) { [[{}, { title: 'Real title' }, plain_item]] }

        it 'is not a no-op and raises no item warning', :aggregate_failures do
          expect(slice.enhance_gains.no_op).to be(false)
          expect(slice.warnings).to eq([])
        end
      end

      {
        'a type chip description' => [{ description: 'Press Release' }, :enhance_category_only_description],
        'a chip padded with whitespace' => [{ description: "  news \n" }, :enhance_category_only_description],
        'a description equal to a category' => [{ description: 'Politics', categories: %w[politics] },
                                                :enhance_category_only_description],
        'a description unrelated to categories' => [{ description: 'Politics today', categories: %w[sports] }, nil],
        'a whitespace-only description' => [{ description: "  \n" }, nil],
        'a prose description' => [{ description: 'A real sentence.' }, nil]
      }.each do |label, (enhanced, warning)|
        context "with #{label}" do
          let(:pairs) { [[{}, enhanced, plain_item]] }

          it "warns #{warning.inspect}" do
            expect(slice.warnings - [:enhance_no_op]).to eq([warning].compact)
          end
        end
      end

      {
        'a single image whose alt equals the description' =>
          ['<img alt=" Sunset " src="a.png">', 'Sunset', [:enhance_image_only_description]],
        'a single image whose alt differs from the description' =>
          ['<img alt="Sunset" src="a.png">', 'A long caption', []],
        'two images with prose' => ['<img alt="a"><img alt="b">', 'A long caption', []],
        'a single image without alt and prose' => ['<img src="a.png">', 'A long caption', []],
        'a filename description' => ['<span>x</span>', 'photo.JPG', [:enhance_image_only_description]],
        'an absolute url description' => ['<span>x</span>', 'HTTPS://cdn.test/a', [:enhance_image_only_description]],
        'a path description' => ['<span>x</span>', '/media/a-b/c.d', [:enhance_image_only_description]],
        'a description without letters' => ['<span>x</span>', '12345', [:enhance_image_only_description]],
        'a prose description starting with a slash' => ['<span>x</span>', '/ and more words', []],
        'a prose description containing a url' => ['<span>x</span>', 'See https://a.test now', []]
      }.each do |label, (html, description, expected)|
        context "with image-only check: #{label}" do
          let(:pairs) { [[{}, { description: }, Nokogiri::HTML.fragment("<li>#{html}</li>").children.first]] }

          it 'warns accordingly' do
            expect(slice.warnings - [:enhance_no_op]).to eq(expected)
          end
        end
      end

      context 'with several flagged items' do
        let(:pairs) do
          [[{}, { description: 'news' }, plain_item], [{}, { description: 'press release' }, plain_item]]
        end

        it 'records one warning per flagged item' do
          expect(slice.warnings).to eq(%i[enhance_category_only_description enhance_category_only_description])
        end
      end
    end

    context 'with rich_card.html' do
      let(:selectors) do
        {
          items: { selector: 'article.card', enhance: true },
          title: { selector: 'h2' },
          url: { selector: 'a', extractor: 'href' }
        }
      end

      it 'counts description gains without junk warnings', :aggregate_failures do
        slice = probe_audit('rich_card.html', selectors)

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
        slice = probe_audit('anchor_item.html', selectors)

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
        slice = probe_audit('no_op.html', selectors)

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
        slice = probe_audit('mixed_listing.html', selectors)

        expect(slice.enhance_gains.no_op).to be(false)
        expect(slice.enhance_gains.descriptions_added).to be >= 1
        expect(slice.warnings).not_to include(:enhance_no_op)
      end
    end
  end

  describe '.compare' do
    let(:selectors) do
      {
        items: { selector: 'article.card', enhance: false },
        title: { selector: 'h2' },
        url: { selector: 'a', extractor: 'href' }
      }
    end

    it 'returns nil without an items selector', :aggregate_failures do
      response = enhance_audit_response('rich_card.html')

      expect(described_class.compare(response:, selectors: nil, time_zone:)).to be_nil
      expect(described_class.compare(response:, selectors: { items: {} }, time_zone:)).to be_nil
    end

    it 'compares enhance off against on and reports the delta', :aggregate_failures do
      response = enhance_audit_response('rich_card.html')
      off = described_class.compare(response:, selectors:, time_zone:)
      probed = described_class.probe(response:, selectors:, time_zone:).enhance_gains

      expect(off[:enhance_off]).to eq(item_count: 2, descriptions_filled: 0)
      expect(off[:enhance_on]).to eq(item_count: 2, descriptions_filled: probed.descriptions_added)
      expect(off[:delta]).to eq(descriptions_gained: probed.descriptions_added, keys_added: probed.keys_added,
                                no_op: probed.no_op)
    end

    it 'does not mutate the caller selectors' do
      response = enhance_audit_response('rich_card.html')
      described_class.compare(response:, selectors:, time_zone:)

      expect(selectors[:items]).to eq(selector: 'article.card', enhance: false)
    end

    it 'reports a zero delta when enhance changes nothing', :aggregate_failures do
      response = enhance_audit_response('no_op.html')
      no_op = { items: { selector: 'div.item', enhance: false }, title: { selector: '.title' },
                url: { selector: '.url', extractor: 'href' }, description: { selector: '.desc' } }
      result = described_class.compare(response:, selectors: no_op, time_zone:)

      expect(result[:delta]).to include(descriptions_gained: 0, no_op: true)
      expect(result[:enhance_off]).to eq(result[:enhance_on])
    end

    it 'falls back to empty gains when the probe yields nothing', :aggregate_failures do
      allow(described_class).to receive(:probe).and_return(nil)
      result = described_class.compare(response: enhance_audit_response('rich_card.html'), selectors:, time_zone:)

      expect(result[:delta]).to include(
        keys_added: { title: 0, url: 0, description: 0, published_at: 0, categories: 0, author: 0, image: 0,
                      id: 0, enclosures: 0 },
        no_op: true
      )
    end
  end

  describe '.empty_gains' do
    it 'is a zeroed no-op', :aggregate_failures do
      expect(described_class.empty_gains).to have_attributes(items_probed: 0, descriptions_added: 0, no_op: true)
      expect(described_class.empty_gains.keys_added.values.uniq).to eq([0])
      expect(described_class.empty_gains.keys_added.keys).to eq(%i[title url description published_at categories
                                                                   author image id enclosures])
    end
  end
end

# rubocop:enable RSpec/ExampleLength, RSpec/NestedGroups, RSpec/MultipleMemoizedHelpers
