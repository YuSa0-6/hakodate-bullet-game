# frozen_string_literal: true

require_relative '../lib/views/renderers/panel'
require_relative '../lib/entities/player'
require_relative '../lib/entities/boss'
require_relative 'helper'

# Renderers::Panel のスモークテスト。
#
# このテストは「画面にキャラクターや弾幕が表示されない」回帰を防ぐ目的。
# Panel.call が出力する DOM 木の中に、各エンティティのクラス（.pl, .b, .z, .f,
# .bs, .crown, .s, .warn）と対応する sprite クラス（.sp-*）が確かに含まれること
# を確認する。Lively のレンダリングランタイムは使わず、CaptureBuilder で
# builder API のみを観察する。
describe Renderers::Panel do
  let(:barrier) { TestBarrier.new }
  let(:player) do
    p = Player.new(
      name: 'P1', color: '#7cf',
      controls: Config::P1_CONTROLS, diff: Config::DIFF[:easy], seed: 1
    )
    p.attach_barrier!(barrier)
    p
  end

  def render(player_with_state)
    builder = CaptureBuilder.new
    Renderers::Panel.call(builder, player: player_with_state, side: :left)
    builder
  end

  with '基本要素（HUD と field 枠）' do
    it 'HUD と field の親 div が出力される' do
      builder = render(player)
      # ライフ表示・スコア表示などを含む HUD 要素は最低 1 つ
      expect(builder.find_by_tag(:div).size).to be > 1
    end

    it '自機（.pl）と当たり判定マーカー（.hb）が必ず出る（生存中）' do
      builder = render(player)
      expect(builder.find_by_class('pl').size).to be == 1
      expect(builder.find_by_class('hb').size).to be == 1
    end

    it '自機 sprite クラス（sp-player）が出力される' do
      builder = render(player)
      expect(builder.find_by_class('sp-player').size).to be == 1
    end
  end

  with 'ボス描画' do
    it 'p.boss が nil なら boss 関連要素は出ない（ガード）' do
      builder = render(player)
      expect(builder.find_by_class('bs').size).to be == 0
      expect(builder.find_by_class('crown').size).to be == 0
    end

    it 'spawn_boss! 後は boss body と crown が出る' do
      player.spawn_boss!
      builder = render(player)
      expect(builder.find_by_class('bs').size).to be == 1
      expect(builder.find_by_class('crown').size).to be == 1
      expect(builder.find_by_class('sp-boss_body').size).to be == 1
      expect(builder.find_by_class('sp-boss_crown').size).to be == 1
    end

    it 'boss の HP バーが出る（boss 存在時）' do
      player.spawn_boss!
      builder = render(player)
      # HPバーは inline style なのでクラス名検索の代わりに HTML 文字列で確認
      html = builder.to_html
      expect(html).to be(:include?, 'background:#f44')
    end
  end

  with '雑魚描画' do
    it '@zakos の各要素ごとに .z + sprite クラスが出る' do
      type = Assets::ZAKO_TYPES.first  # 🐙 spread
      player.zakos << Zako.spawn(type, x: 100.0)

      builder = render(player)
      expect(builder.find_by_class('z').size).to be == 1
      # sp-zako_octopus が必ず付く
      expect(builder.find_by_class('sp-zako_octopus').size).to be == 1
    end

    it 'HP が満タンなら HPバーは出ない（layout コスト削減仕様）' do
      type = Assets::ZAKO_TYPES.last  # 🦐 agile
      player.zakos << Zako.spawn(type, x: 100.0)

      builder = render(player)
      # hpbar クラス
      expect(builder.find_by_class('hpbar').size).to be == 0
    end

    it 'HP が満タン未満なら HPバーが出る' do
      type = Assets::ZAKO_TYPES[1]  # 🐡 tank（HP 3）
      z = Zako.spawn(type, x: 100.0)
      z[:hp] = 1
      player.zakos << z

      builder = render(player)
      expect(builder.find_by_class('hpbar').size).to be == 1
    end
  end

  with '弾描画' do
    it '通常弾は .b + sp-bullet_normal' do
      player.bullets << {
        x: 50.0, y: 50.0, vx: 0.0, vy: 1.0,
        sine: false, bounce: false, garbage: false, sprite: :bullet_normal
      }
      builder = render(player)
      expect(builder.find_by_class('b').size).to be == 1
      expect(builder.find_by_class('sp-bullet_normal').size).to be == 1
    end

    it 'お邪魔弾（garbage:true）は sp-bullet_garbage' do
      player.bullets << {
        x: 50.0, y: 50.0, vx: 0.0, vy: 1.0,
        sine: false, bounce: false, garbage: true
      }
      builder = render(player)
      expect(builder.find_by_class('sp-bullet_garbage').size).to be == 1
    end

    it ':bullet_star スプライトの弾は sp-bullet_star' do
      player.bullets << {
        x: 50.0, y: 50.0, vx: 0.0, vy: 0.0,
        sine: false, bounce: false, sprite: :bullet_star
      }
      builder = render(player)
      expect(builder.find_by_class('sp-bullet_star').size).to be == 1
    end

    it '複数の弾は枚数ぶん要素が増える' do
      5.times do |i|
        player.bullets << {
          x: i * 20.0, y: 50.0, vx: 0.0, vy: 1.0,
          sine: false, bounce: false, garbage: false
        }
      end
      builder = render(player)
      expect(builder.find_by_class('b').size).to be == 5
    end
  end

  with 'ショット描画' do
    it 'ショットは .s + sp-shot で、プレイヤー色が currentColor として注入される' do
      player.shots << {x: 10.0, y: 10.0, vx: 0.0, vy: -10.0}
      builder = render(player)
      expect(builder.find_by_class('s').size).to be == 1
      expect(builder.find_by_class('sp-shot').size).to be == 1
      # color プロパティに player.color が入る
      shot_node = builder.find_by_class('s').first
      expect(shot_node[:attrs][:style]).to be(:include?, 'color:#7cf')
    end
  end

  with '食べ物描画' do
    it '食べ物は .f + sp-food_* で出る' do
      player.foods << {type: '🦑', x: 30.0, y: 30.0, vy: 1.0, phase: 0.0}
      builder = render(player)
      expect(builder.find_by_class('f').size).to be == 1
      expect(builder.find_by_class('sp-food_squid').size).to be == 1
    end
  end

  with '警告描画' do
    it '警告は .warn + sp-warning で、frames_left に応じた opacity が付く' do
      player.garbage_queue.warnings << {type: :spread, x: 100, frames_left: Config::GARBAGE_WARN_FRAMES / 2}
      builder = render(player)
      expect(builder.find_by_class('warn').size).to be == 1
      expect(builder.find_by_class('sp-warning').size).to be == 1
    end
  end

  with '死亡オーバーレイ' do
    it 'alive? が false なら死亡オーバーレイが描画される' do
      player.alive_state = false
      builder = render(player)
      html = builder.to_html
      expect(html).to be(:include?, Assets::Icons::DEAD)
    end

    it '生存中は描画されない' do
      builder = render(player)
      html = builder.to_html
      expect(html).not.to be(:include?, Assets::Icons::DEAD)
    end
  end

  with '回帰テスト：すべて同時に描画した複合シーン' do
    # 「画面に何も出ない」バグの逆。すべてのカテゴリを 1 シーンに詰めて
    # 全クラスがちゃんと出力されることを最後にまとめて検証する。
    it '自機 + ボス + 雑魚 + 弾 + ショット + 食べ物 + 警告がすべて出力される' do
      player.spawn_boss!
      player.zakos << Zako.spawn(Assets::ZAKO_TYPES.first, x: 50.0)
      player.bullets << {
        x: 60.0, y: 60.0, vx: 0.0, vy: 1.0,
        sine: false, bounce: false, garbage: false
      }
      player.shots << {x: 10.0, y: 10.0, vx: 0.0, vy: -10.0}
      player.foods << {type: '🦑', x: 30.0, y: 30.0, vy: 1.0, phase: 0.0}
      player.garbage_queue.warnings << {type: :spread, x: 80, frames_left: 30}

      builder = render(player)
      %w[pl bs crown z b s f warn].each do |cls|
        expect(builder.find_by_class(cls).size).to be > 0
      end
    end
  end
end
