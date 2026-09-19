# frozen_string_literal: true

module McpTestHelpers
  def report(**data)
    Html2rss::PageRecon::Diagnostics::Report.new(
      data: { articles_count: 0, alternate_feeds: [], **data }
    )
  end

  # rubocop:disable-next Metrics/MethodLength -- fixture builder for recon Result
  def recon_result(verdict:, **attrs)
    Html2rss::Recon::Result.new(
      requested_url: 'https://example.com',
      final_url: 'https://example.com',
      status: 200,
      verdict: Html2rss::Recon::Verdict.coerce(verdict),
      native_feed: nil,
      surface_category: :article_listing,
      articles_count: 3,
      scheme_downgrade: false,
      notes: [],
      html_bytesize: 1000,
      **attrs
    )
  end

  # rubocop:disable-next Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity -- fixture builder for test Result
  def test_result(success: false, failure_kind: nil, validation_issues: :unset, sample_items: :unset,
                  error_message: nil, **)
    issues =
      if validation_issues != :unset
        validation_issues
      elsif success
        nil
      else
        [Html2rss::Config::ValidationIssue.new(path: %i[channel], code: :missing_key, message: 'is missing')]
      end

    samples =
      if sample_items != :unset
        sample_items
      elsif success
        [{ title: 'A', url: 'https://example.com/a' }]
      else
        []
      end

    msg =
      if success
        nil
      else
        error_message || 'Configuration schema validation failed'
      end

    Html2rss::Test::Result.new(
      success:,
      failure_kind:,
      item_count: success ? 2 : 0,
      sample_items: samples,
      channel_title: 'Example',
      channel_url: 'https://example.com',
      strategy_used: :default,
      duration_seconds: 0.1,
      validation_issues: issues,
      error_message: msg,
      rss: success ? '<rss/>' : nil,
      **
    )
  end
end
