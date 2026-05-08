# frozen_string_literal: true

require_relative '../lib/sprites'
require_relative '../lib/views/renderers/panel'

# Sprites の仕様。
#
# all_css に含まれる CSS クラス名と、Renderers::Panel が出力する
# class 名（および Sprites::ZAKO_SPRITES / FOOD_SPRITES のテーブル）が
# 必ず対応していることを保証する。
#
# 「画面に何も出ない」典型原因は、
#   * Sprites.all_css のキー（sp-xxx）が抜けている
#   * panel.rb 側が参照する sprite キーがテーブルに無い
# のどちらか。両者を機械的に突き合わせる。
describe Sprites do
  with '.class_name' do
    it 'sp- プレフィックスを付けて返す' do
      expect(Sprites.class_name(:player)).to be == 'sp-player'
      expect(Sprites.class_name(:bullet_normal)).to be == 'sp-bullet_normal'
    end
  end

  with '.all_css' do
    let(:css) { Sprites.all_css }

    it 'すべての ART キーに対応する .sp-* セレクタを生成する' do
      Sprites::ART.each_key do |name|
        cls = Sprites.class_name(name)
        expect(css).to be(:include?, ".#{cls} ")
      end
    end

    it 'data:image/svg+xml;base64 形式の data URI を含む（壊れた form encoding ではない）' do
      expect(css).to be(:include?, 'data:image/svg+xml;base64,')
    end

    it 'shot だけは mask 方式（プレイヤー色を currentColor で反映）' do
      expect(css).to be(:include?, '.sp-shot {')
      expect(css).to be(:include?, 'background-color:currentColor')
    end
  end

  with '.svg（ART → SVG 変換）' do
    it '透明 (.) は出力されない（rect 数の抑制）' do
      art = "..\n..\n"
      expect(Sprites.svg(art)).not.to be(:include?, '<rect')
    end

    it '同色は横方向に RLE で連結される（rect 数 = 行ごとに 1 個になる）' do
      art = "WWWW\nWWWW\n"
      svg = Sprites.svg(art)
      # 4列同色 → 行ごとに 1 rect → 全部で 2 rect
      expect(svg.scan(/<rect/).size).to be == 2
    end
  end

  with 'PALETTE と ART の整合性' do
    it 'ART 内に出てくる文字はすべて . か PALETTE のキー' do
      Sprites::ART.each do |name, art|
        chars = art.chars.reject { |c| c == "\n" || c == '.' }.uniq
        chars.each do |c|
          unless Sprites::PALETTE.key?(c)
            raise "Sprite #{name} uses character #{c.inspect} which is not in PALETTE"
          end
        end
      end
    end
  end

  with 'Renderers::Panel との整合性（回帰防止）' do
    # panel.rb の SP_* 定数がすべて Sprites::ART に存在することを保証する。
    # ここがズレると「クラスは出るのに背景画像が当たらない＝透明 0×0」になり、
    # 画面に何も見えないバグが発生する。
    it 'Panel の SP_* 定数はすべて ART キーに対応する' do
      sp_consts = Renderers::Panel.constants.grep(/\ASP_/)
      sp_consts.each do |const|
        cls = Renderers::Panel.const_get(const)
        sprite_name = cls.delete_prefix('sp-').to_sym
        unless Sprites::ART.key?(sprite_name)
          raise "Panel::#{const} = #{cls.inspect} だが Sprites::ART に :#{sprite_name} が無い"
        end
      end
    end

    it 'ZAKO_SPRITES の値はすべて ART キー' do
      Sprites::ZAKO_SPRITES.each_value do |sprite|
        expect(Sprites::ART).to be(:key?, sprite)
      end
    end

    it 'FOOD_SPRITES の値はすべて ART キー' do
      Sprites::FOOD_SPRITES.each_value do |sprite|
        expect(Sprites::ART).to be(:key?, sprite)
      end
    end
  end
end
