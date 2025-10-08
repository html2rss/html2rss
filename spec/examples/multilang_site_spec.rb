# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Multi-Language Site Configuration' do
  subject(:feed) do
    mock_request_service_with_html_fixture('multilang_site', 'https://example.com')
    Html2rss.feed(config)
  end

  let(:config_file) { File.join(%w[spec examples multilang_site.yml]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }
  let(:channel_url) { config.dig(:channel, :url) }
  let(:items) { feed.items }
  let(:expected_titles) do
    [
      "[en] Breaking News: ACME Corp's Technology Update",
      '[es] Noticias: Actualización Tecnológica de ACME Corp',
      "[fr] Actualités: Mise à jour technologique d'ACME Corp",
      '[de] Nachrichten: ACME Corp Technologie-Update',
      '[en] Environmental Research Update',
      '[es] Investigación Ambiental Actualizada',
      '[en] Health and Wellness Guide',
      '[fr] Guide Santé et Bien-être'
    ]
  end

  let(:expected_descriptions) do
    [
      "This is a major technology breakthrough that will change everything. ACME Corp scientists have developed a new quantum computing algorithm that promises to revolutionize data processing. It can finally solve the halting problem... or can it? The new system can process complex calculations in seconds that would take traditional computers years to complete. It's so fast, it can compile Hello World before you finish typing it.",
      "Esta es una gran innovación tecnológica que cambiará todo. Los científicos de ACME Corp han desarrollado un nuevo algoritmo de computación cuántica que promete revolucionar el procesamiento de datos. Es tan avanzado que puede debuggear código antes de que se escriba. El nuevo sistema puede procesar cálculos complejos en segundos que tomarían años a las computadoras tradicionales. También viene con una taza de café integrada.",
      "Il s'agit d'une percée technologique majeure qui va tout changer. Les scientifiques d'ACME Corp ont développé un nouvel algorithme de calcul quantique qui promet de révolutionner le traitement des données. Il peut même comprendre le code français. Le nouveau système peut traiter des calculs complexes en quelques secondes qui prendraient des années aux ordinateurs traditionnels. Il est si rapide qu'il peut compiler \"Bonjour le monde\" avant que vous ne finissiez de le taper.",
      "Dies ist ein wichtiger technologischer Durchbruch, der alles verändern wird. Wissenschaftler von ACME Corp haben einen neuen Quantencomputing-Algorithmus entwickelt, der die Datenverarbeitung revolutionieren soll. Er kann sogar deutsche Kommentare verstehen. Das neue System kann komplexe Berechnungen in Sekunden verarbeiten, für die herkömmliche Computer Jahre benötigen würden. Es ist so schnell, dass es \"Hallo Welt\" kompilieren kann, bevor Sie es fertig getippt haben.",
      'New research shows that climate change is accelerating faster than previously predicted. The study, conducted by an international team of scientists, reveals alarming trends in global temperature rise. Immediate action is required to prevent catastrophic environmental damage within the next decade.',
      'Nueva investigación muestra que el cambio climático se está acelerando más rápido de lo previsto. El estudio, realizado por un equipo internacional de científicos, revela tendencias alarmantes en el aumento de la temperatura global. Se requiere acción inmediata para prevenir daños ambientales catastróficos en la próxima década.',
      'Maintaining good health requires a balanced approach to diet, exercise, and mental well-being. Recent studies have shown the importance of regular physical activity and proper nutrition. Experts recommend at least 30 minutes of moderate exercise daily, combined with a diet rich in fruits, vegetables, and whole grains.',
      "Maintenir une bonne santé nécessite une approche équilibrée de l'alimentation, de l'exercice et du bien-être mental. Des études récentes ont montré l'importance de l'activité physique régulière et d'une nutrition appropriée. Les experts recommandent au moins 30 minutes d'exercice modéré quotidien, combiné avec un régime riche en fruits, légumes et céréales complètes."
    ]
  end

  let(:expected_categories) do
    [
      ['en', 'Technology'],
      ['es', 'Tecnología'],
      ['fr', 'Technologie'],
      ['de', 'Technologie'],
      ['en', 'Environment'],
      ['es', 'Medio Ambiente'],
      ['en', 'Health'],
      ['fr', 'Santé']
    ]
  end

  it 'applies the configured channel metadata' do
    expect(feed.channel.title).to eq('ACME Multi-Language Site News')
    expect(feed.channel.link).to eq('https://example.com')
    expect(feed.channel.language).to eq('en')
  end

  it 'renders every post with language-prefixed titles and sanitised body copy', :aggregate_failures do
    expect(items.size).to eq(expected_titles.size)
    expect(items.map(&:title)).to eq(expected_titles)
    expect(items.map(&:description)).to eq(expected_descriptions)
  end

  it 'exposes language codes and translated topics as individual categories' do
    expect(items.map { |item| item.categories.map(&:content) })
      .to eq(expected_categories)
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
