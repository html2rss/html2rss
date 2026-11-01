# frozen_string_literal: true

require 'tmpdir'

RSpec.describe Html2rss::Capture, 'scaling' do # rubocop:disable RSpec/DescribeMethod
  let(:ancestor_steps_for) do
    lambda do |cards|
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'listing.html')
        card = lambda { |i|
          body = Array.new(120) { |w| "lorem#{((i * 7) + w) % 997}" }.join(' ')
          title = "Breaking news about topic number #{i} in the region today"
          %(<article><h3><a href="/p/#{i}">#{title}</a></h3><p>#{body}</p></article>)
        }
        File.write(path, "<html><body><main>#{Array.new(cards, &card).join}</main></body></html>")
        steps = 0
        allow_any_instance_of(Html2rss::SST::Index).to receive(:parent_of).and_wrap_original do |orig, *args| # rubocop:disable RSpec/AnyInstance
          steps += 1
          orig.call(*args)
        end
        described_class.build('https://example.com/', strategy: :local_file, local_file_path: path, force: true)
        steps
      end
    end
  end

  it 'walks SST ancestors no faster than linearly as the listing doubles', :aggregate_failures do
    small = ancestor_steps_for.call(40)
    large = ancestor_steps_for.call(80)

    expect(small).to be_positive
    expect(large.fdiv(small)).to be < 2.6
  end
end
