# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Segmenter::Cluster::OverlapResolver do
  subject(:resolver) { described_class.new(index: document.index) }

  let(:document) { document_for(html) }
  let(:nodes_named) { ->(name) { document.index.each_node.select { |node| node.name.to_s == name }.to_a } }

  describe '#filter_containers' do
    context 'when a group encloses several nodes of another layout group' do
      let(:html) do
        '<html><body><section><div>one</div><div>two</div></section></body></html>'
      end

      it 'drops the enclosing group', :aggregate_failures do
        groups = { 'wrap' => nodes_named.call('section'), 'card' => nodes_named.call('div') }

        expect(resolver.filter_containers(groups).keys).to eq(['card'])
      end
    end

    context 'when a group encloses its nodes through intermediate ancestors' do
      let(:html) do
        '<html><body><section><span><div>one</div></span><span><div>two</div></span></section></body></html>'
      end

      it 'drops the enclosing group', :aggregate_failures do
        groups = { 'wrap' => nodes_named.call('section'), 'card' => nodes_named.call('div') }

        expect(resolver.filter_containers(groups).keys).to eq(['card'])
      end
    end

    context 'when only some nodes of a group enclose several nodes of another group' do
      let(:html) do
        '<html><body><section><div>one</div><div>two</div></section><section>plain</section></body></html>'
      end

      it 'drops the group', :aggregate_failures do
        groups = { 'wrap' => nodes_named.call('section'), 'card' => nodes_named.call('div') }

        expect(resolver.filter_containers(groups).keys).to eq(['card'])
      end
    end

    context 'when each node of a group encloses only one node of the other group' do
      let(:html) do
        '<html><body><section><div>one</div></section><section><div>two</div></section></body></html>'
      end

      it 'keeps both groups', :aggregate_failures do
        groups = { 'wrap' => nodes_named.call('section'), 'card' => nodes_named.call('div') }

        expect(resolver.filter_containers(groups).keys).to eq(%w[wrap card])
      end
    end

    context 'when structurally identical wrappers each enclose one identical node' do
      let(:html) do
        '<html><body><section><div>same</div></section><section><div>same</div></section></body></html>'
      end

      it 'counts each wrapper on its own', :aggregate_failures do
        groups = { 'wrap' => nodes_named.call('section'), 'card' => nodes_named.call('div') }

        expect(resolver.filter_containers(groups).keys).to eq(%w[wrap card])
      end
    end

    context 'when the enclosed group is not made of layout tags' do
      let(:html) { '<html><body><section><p>one</p><p>two</p></section></body></html>' }

      it 'keeps the enclosing group' do
        groups = { 'wrap' => nodes_named.call('section'), 'text' => nodes_named.call('p') }

        expect(resolver.filter_containers(groups).keys).to eq(%w[wrap text])
      end
    end
  end
end
