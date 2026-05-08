# frozen_string_literal: true

require_relative '../lib/views/renderers/center_gauge'
require_relative '../lib/views/renderers/screens'
require_relative '../lib/game/battle'
require_relative 'helper'

# CenterGauge / Screens のスモークテスト。
# Panel と同様に「中央 UI / タイトル / 結果画面が描画されない」回帰を防ぐ。
# Lively のレンダリングランタイムは使わず、CaptureBuilder で出力を観察する。

describe Renderers::CenterGauge do
  let(:barrier) { TestBarrier.new }
  let(:battle)  { Battle.new(difficulty: :easy, barrier: barrier) }

  def render(b)
    builder = CaptureBuilder.new
    Renderers::CenterGauge.call(builder, battle: b)
    builder
  end

  with 'wave フェーズ' do
    it 'WAVE 残り秒数表示と両プレイヤーのゲージ枠が出る' do
      builder = render(battle)
      html = builder.to_html
      # WAVE ラベル（フェーズ表示）
      expect(html).to be(:include?, 'WAVE')
      # 累計送出ゲージの矢印（P1: ↑ / P2: ↓）
      expect(html).to be(:include?, '↑0')
      expect(html).to be(:include?, '↓0')
    end
  end

  with 'boss フェーズ' do
    it '⚔ BOSS ⚔ ラベルが出る（WAVE ラベルではない）' do
      battle.instance_variable_set(:@phase, :boss)
      builder = render(battle)
      html = builder.to_html
      expect(html).to be(:include?, 'BOSS')
      expect(html).not.to be(:include?, 'WAVE')
    end
  end

  with '送出量表示' do
    it 'p1.total_sent / p2.total_sent の数値が表示される' do
      battle.p1.total_sent = 7
      battle.p2.total_sent = 12
      builder = render(battle)
      html = builder.to_html
      expect(html).to be(:include?, '↑7')
      expect(html).to be(:include?, '↓12')
    end
  end
end

describe Renderers::Screens do
  def render_title(diff)
    builder = CaptureBuilder.new
    Renderers::Screens.title(builder, difficulty: diff)
    builder
  end

  def render_result(battle)
    builder = CaptureBuilder.new
    Renderers::Screens.result(builder, battle: battle)
    builder
  end

  with '.title' do
    it '全難易度ラベル（EASY/NORMAL/HARD）が並ぶ' do
      html = render_title(:easy).to_html
      Config::DIFFICULTIES.each do |dk|
        expect(html).to be(:include?, Config::DIFF[dk][:label])
      end
    end

    it '操作説明（P1 / P2）が出る' do
      html = render_title(:normal).to_html
      expect(html).to be(:include?, 'P1')
      expect(html).to be(:include?, 'P2')
      expect(html).to be(:include?, 'WASD')
    end

    it '選択中の難易度ラベルだけ強調表示される' do
      html = render_title(:hard).to_html
      # hard 色 #f44336 は難易度説明文に含まれる
      expect(html).to be(:include?, '#f44336')
    end
  end

  with '.result' do
    let(:barrier) { TestBarrier.new }
    let(:battle)  { Battle.new(difficulty: :easy, barrier: barrier) }

    it ':p1 winner で TROPHY と P1 WIN! が表示される' do
      battle.instance_variable_set(:@winner, :p1)
      html = render_result(battle).to_html
      expect(html).to be(:include?, 'P1 WIN!')
    end

    it ':draw で SCALE と DRAW が表示される' do
      battle.instance_variable_set(:@winner, :draw)
      html = render_result(battle).to_html
      expect(html).to be(:include?, 'DRAW')
    end

    it '両プレイヤーのスコア・送出数・残機が表示される' do
      battle.p1.score      = 1234
      battle.p1.total_sent = 5
      battle.p2.score      = 999
      battle.p2.total_sent = 3
      battle.instance_variable_set(:@winner, :p2)
      html = render_result(battle).to_html
      expect(html).to be(:include?, '1234')
      expect(html).to be(:include?, '999')
      expect(html).to be(:include?, 'SENT   5')
      expect(html).to be(:include?, 'SENT   3')
    end
  end
end
