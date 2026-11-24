# frozen_string_literal: true

RSpec.describe 'Russian date pieces' do # rubocop:disable RSpec/DescribeClass
  let(:ru) { Html2rss::Vocabulary[:ru] }

  {
    '12 ноября' => true, '12 ноября 2026' => true, '1 мая' => true, '5 янв.' => true, '12 нояб. 2026' => true,
    'ноябрь 2026' => true, 'Ноябрь 2026' => true, 'сегодня' => true, 'Вчера' => true, 'вчера в 14:30' => true,
    'Сегодня 9:05' => true, ' 12 ноября ' => true,
    'Сегодня в Москве открылась выставка' => false, 'Май стал самым тёплым' => false, 'Май' => false,
    'ноябрь' => false, '12 ноября состоится матч' => false, 'вчера в Москве' => false,
    '12 ноября 2026 года власти заявили' => false, '14:30' => false, '12 November' => false
  }.each do |text, expected|
    it "is #{expected} for #{text.inspect}" do
      expect(Html2rss::Article::Title.date_piece?(text, vocabulary: ru, date_element: true)).to be(expected)
    end
  end
end
