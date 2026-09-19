# frozen_string_literal: true

module FeedTestHelpers
  def html_response(body, page_url: 'https://example.com/blog', content_type: 'text/html', status: 200)
    Html2rss::RequestService::Response.new(
      body:,
      url: Html2rss::Url.from_absolute(page_url),
      headers: { 'content-type' => content_type },
      status:
    )
  end

  def feed_response(body:, content_type:, status: 200, url: 'https://example.com/feed')
    Html2rss::RequestService::Response.new(
      body:,
      headers: { 'content-type' => content_type },
      url: Html2rss::Url.from_absolute(url),
      status:
    )
  end

  # rubocop:disable-next Metrics/ParameterLists -- mock helper with default options
  def stub_outcome(response, articles:, admission_drops: {}, selected_strategy: nil, scrape_target: nil,
                   url: 'https://example.com/blog')
    target = scrape_target || Html2rss::ScrapeTarget.new(entry_url: url, effective_url: url)
    outcome = instance_double(
      Html2rss::FeedPipeline::PipelineOutcome,
      response:, articles:, admission_drops:, selected_strategy:, scrape_target: target
    )
    allow(Html2rss::FeedPipeline).to receive(:new)
      .and_return(instance_double(Html2rss::FeedPipeline, to_outcome: outcome))
    outcome
  end

  def assessment(surface_category:, articles_count:, admission_drops: {})
    Html2rss::PageRecon::Assessment.new(
      surface_category:,
      articles_count:,
      admission_drops:,
      html_response: true
    )
  end

  def scored_probe(url:, score:, articles_count:)
    Html2rss::FeedResolution::Probe::Scored.new(
      url: Html2rss::Url.from_absolute(url),
      score:,
      articles_count:
    )
  end
  alias scored scored_probe

  def rss_channel_item(title:, url:)
    instance_double(RSS::Rss::Channel::Item, title:, link: url)
  end
  alias rss_item rss_channel_item

  def classifier_for(*segments)
    Html2rss::LinkDestination::PathClassifier.new(segments)
  end

  def mock_session(*xml_bodies)
    session = instance_double(Html2rss::RequestSession)
    responses = xml_bodies.map { |xml| instance_double(Html2rss::RequestService::Response, body: xml) }
    allow(session).to receive(:follow_up).and_return(*responses)
    session
  end

  def mock_sitemap_response(xml)
    instance_double(Html2rss::RequestService::Response, body: xml)
  end

  def request_session_context(url: 'https://example.com/news', max_requests: 3)
    policy = Html2rss::RequestService::Policy.new(max_requests:)
    budget = Html2rss::RequestService::Budget.new(max_requests: policy.max_requests)
    Html2rss::RequestService::Context.new(url:, headers: { 'User-Agent' => 'RSpec' }, policy:, budget:)
  end
end
