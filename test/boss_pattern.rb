# frozen_string_literal: true

require_relative '../lib/entities/boss'
require_relative 'helper'

# Boss の弾幕パターン（private メソッド群）の挙動。
# 既存 test/boss.rb は HP・移動・フェーズ判定だけを見ており、実際に出る弾の
# 数・性質は未検証だった。ここでは sink を lambda で受け取り、生成された弾の
# 配列を直接観察する。
#
# private メソッドは `send` で呼ぶ（私的 API への結合は許容範囲：弾幕の
# 仕様変更が起きたらここが赤くなる、というのが狙い）。
describe Boss do
  let(:boss) { Boss.new(diff: Config::DIFF[:easy]) }
  let(:diff) { Config::DIFF[:easy] }

  with '#fire_squid_spread（イカ墨拡散）' do
    it '@diff[:squid] の数だけ弾を生成する' do
      bullets = []
      boss.send(:fire_squid_spread, ->(b) { bullets << b })
      expect(bullets.size).to be == diff[:squid]
    end

    it '生成された弾は下向き（vy = @diff[:squid_vy]）' do
      bullets = []
      boss.send(:fire_squid_spread, ->(b) { bullets << b })
      expect(bullets).to be(:all?) { |b| b[:vy] == diff[:squid_vy] }
      expect(bullets).to be(:all?) { |b| b[:vx] == 0.0 }
    end

    it '弾は横に等間隔で散らばっている（拡散弾の本質）' do
      bullets = []
      boss.send(:fire_squid_spread, ->(b) { bullets << b })
      xs = bullets.map { |b| b[:x] }
      gaps = xs.each_cons(2).map { |a, b| (b - a).round(3) }
      # 等間隔なら gap の集合は 1 種類
      expect(gaps.uniq.size).to be == 1
    end
  end

  with '#fire_ramen_burst（ラーメン乱打）' do
    it '@diff[:ramen] の数だけサイン波弾を生成する' do
      bullets = []
      boss.send(:fire_ramen_burst, ->(b) { bullets << b })
      expect(bullets.size).to be == diff[:ramen]
      expect(bullets).to be(:all?) { |b| b[:sine] == true }
    end
  end

  with '#fire_sushi_aim（自機狙い）' do
    it '@diff[:sushi] 発の弾を生成し、すべて vy > 0（下向き成分）を持つ' do
      bullets = []
      tx = 100.0
      ty = 600.0
      boss.send(:fire_sushi_aim, ->(b) { bullets << b }, tx, ty)
      expect(bullets.size).to be == diff[:sushi]
      expect(bullets).to be(:all?) { |b| b[:vy] > 0 }
    end

    it '中央弾の vx 符号は target が右にあるなら正、左なら負' do
      right_target = []
      boss.send(:fire_sushi_aim, ->(b) { right_target << b }, 600.0, 600.0)
      left_target = []
      boss.send(:fire_sushi_aim, ->(b) { left_target << b }, -100.0, 600.0)

      mid_r = right_target[diff[:sushi] / 2]
      mid_l = left_target[diff[:sushi] / 2]
      expect(mid_r[:vx]).to be > 0
      expect(mid_l[:vx]).to be < 0
    end
  end

  with '#fire_burger_radial（ラッキー放射）' do
    it 'easy では @diff[:burger_arms] 発（追加旋回なし）' do
      bullets = []
      boss.send(:fire_burger_radial, ->(b) { bullets << b })
      # easy の burger_extra=false かつ phase は 1 のまま（HP 満タン）→ 追加分は出ない
      expect(bullets.size).to be == diff[:burger_arms]
    end

    it 'phase 3 では追加の旋回弾が出る（弾数が倍になる）' do
      # HP を 70% 削ると phase 3
      boss.damage((boss.max_hp * 0.7).to_i)
      bullets = []
      boss.send(:fire_burger_radial, ->(b) { bullets << b })
      expect(bullets.size).to be == diff[:burger_arms] * 2
    end
  end

  with '#spawn_star_formation（星形フォーメーション）' do
    it '5角星の頂点 10 発を生成し、[bullet, 散開角] のペアを返す' do
      bullets = []
      pairs = boss.send(:spawn_star_formation, ->(b) { bullets << b })
      expect(bullets.size).to be == 10
      expect(pairs.size).to be == 10
      # 静止弾（vx=vy=0）
      expect(bullets).to be(:all?) { |b| b[:vx] == 0.0 && b[:vy] == 0.0 }
      # bullet_star スプライトを使う
      expect(bullets).to be(:all?) { |b| b[:sprite] == :bullet_star }
    end
  end

  with '#fire_bento（弁当 bounce 弾）' do
    it 'bounce フラグ付きで 1 発生成し、画面端から内側へ進む' do
      bullets = []
      boss.send(:fire_bento, ->(b) { bullets << b })
      expect(bullets.size).to be == 1
      b = bullets.first
      expect(b[:bounce]).to be == true
      # x=0 なら vx>0、画面右端なら vx<0
      if b[:x] == 0.0
        expect(b[:vx]).to be > 0
      else
        expect(b[:vx]).to be < 0
      end
    end
  end

  with '#bullet（生成弾の構造）' do
    it 'デフォルトは bullet_normal スプライト・sine/bounce off' do
      b = boss.send(:bullet, 0.0, 0.0, 0.0, 0.0)
      expect(b[:sprite]).to be == :bullet_normal
      expect(b[:sine]).to be == false
      expect(b[:bounce]).to be == false
    end

    it ':bullet_star を sprite に渡せば star スプライトになる' do
      b = boss.send(:bullet, 0.0, 0.0, 0.0, 0.0, sprite: :bullet_star)
      expect(b[:sprite]).to be == :bullet_star
    end
  end
end
