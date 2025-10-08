# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Multi-Language Site Configuration' do
  subject(:feed) do
    mock_request_service_with_html_fixture('multilang_site', 'https://example.com')
    Html2rss.feed(config)
  end

  let(:config_file) { File.join(%w[spec examples multilang_site.yml]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }
  let(:items) { feed.items }

  let(:expected_items) do
    [
      {
        title: "[en] Breaking News: ACME Corp's Technology Update",
        description_includes: [
          'quantum computing algorithm that promises to revolutionize data processing',
          "It's so fast, it can compile Hello World before you finish typing it."
        ],
        categories: %w[en Technology]
      },
      {
        title: '[es] Noticias: Actualización Tecnológica de ACME Corp',
        description_includes: [
          'gran innovación tecnológica',
          'También viene con una taza de café integrada.'
        ],
        categories: %w[es Tecnología]
      },
      {
        title: "[fr] Actualités: Mise à jour technologique d'ACME Corp",
        description_includes: [
          'percée technologique majeure',
          "Il est si rapide qu'il peut compiler \"Bonjour le monde\""
        ],
        categories: %w[fr Technologie]
      },
      {
        title: '[de] Nachrichten: ACME Corp Technologie-Update',
        description_includes: [
          'wichtiger technologischer Durchbruch',
          'Es ist so schnell, dass es "Hallo Welt" kompilieren kann'
        ],
        categories: %w[de Technologie]
      },
      {
        title: '[en] Environmental Research Update',
        description_includes: [
          'climate change is accelerating faster than previously predicted',
          'Immediate action is required'
        ],
        categories: %w[en Environment]
      },
      {
        title: '[es] Investigación Ambiental Actualizada',
        description_includes: [
          'El estudio, realizado por un equipo internacional de científicos',
          'Se requiere acción inmediata'
        ],
        categories: ['es', 'Medio Ambiente']
      },
      {
        title: '[en] Health and Wellness Guide',
        description_includes: [
          'Maintaining good health requires a balanced approach',
          'Experts recommend at least 30 minutes of moderate exercise daily'
        ],
        categories: %w[en Health]
      },
      {
        title: '[fr] Guide Santé et Bien-être',
        description_includes: [
          'Maintenir une bonne santé nécessite une approche équilibrée',
          'Les experts recommandent au moins 30 minutes d\'exercice modéré quotidien'
        ],
        categories: %w[fr Santé]
      }
    ]
  end

  it 'applies the configured channel metadata' do
    expect(feed.channel.title).to eq('ACME Multi-Language Site News')
    expect(feed.channel.link).to eq('https://example.com')
    expect(feed.channel.language).to eq('en')
  end

  it 'renders every post with language-prefixed titles and sanitised body copy' do
    expect_feed_items(items, expected_items)
  end

  it 'keeps multilingual content grouped correctly' do
    groups = items.group_by { |item| item.categories.first.content }
    expect(groups.transform_values(&:count)).to eq('en' => 3, 'es' => 2, 'fr' => 2, 'de' => 1)
  end

  it 'retains the source language copy within descriptions' do
    spanish_item = items.find { |item| item.title.start_with?('[es]') }
    french_item = items.find { |item| item.title.start_with?('[fr]') }

    expect(spanish_item.description).to include('Los científicos de ACME Corp han desarrollado')
    expect(french_item.description).to include("Les scientifiques d'ACME Corp ont développé")
  end
end
