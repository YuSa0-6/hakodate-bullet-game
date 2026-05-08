# frozen_string_literal: true

require_relative '../lib/entities/boss'

# ボス（イカ大王 🦑）の仕様。
# HP 比率で 3 段階のフェーズが切り替わり、弾幕パターンが追加される。
describe Boss do
  let(:boss) { Boss.new(diff: Config::DIFF[:easy]) }

  with '初期状態' do
    it '満タン HP・生きている' do
      expect(boss.hp).to be == Config::DIFF[:easy][:boss_hp]
      expect(boss).to be(:alive?)
      expect(boss).not.to be(:dead?)
    end

    it '画面中央上部に出現する' do
      expect(boss.x).to be == Config::FIELD_W / 2.0 - Config::BOSS_W / 2.0
      expect(boss.y).to be == 24.0
    end

    it '左右移動速度は難易度から取得される' do
      expect(boss.vx).to be == Config::DIFF[:easy][:boss_vx]
    end
  end

  with '#damage' do
    it 'HP を減らし、被弾フラッシュを 3 frame 立てる' do
      boss.damage(50)

      expect(boss.hp).to be == Config::DIFF[:easy][:boss_hp] - 50
      expect(boss.flash).to be == 3
    end

    it 'HP が 0 以下になると dead? が true になる（alive? が false）' do
      boss.damage(boss.max_hp)

      expect(boss).to be(:dead?)
      expect(boss).not.to be(:alive?)
    end
  end

  with '#hp_ratio' do
    it '満タンなら 1.0' do
      expect(boss.hp_ratio).to be == 1.0
    end

    it '半分なら 0.5（誤差なし）' do
      boss.damage(boss.max_hp / 2)

      expect(boss.hp_ratio).to be == 0.5
    end

    it 'マイナス HP でも 0.0 にクランプされる（負値を出さない契約）' do
      boss.damage(boss.max_hp + 100)

      expect(boss.hp_ratio).to be == 0.0
    end
  end

  with '#phase（HP 比率による段階切替）' do
    it '0.66 < ratio なら phase 1（spread + sushi のみ）' do
      expect(boss.phase).to be == 1
    end

    it '0.33 < ratio <= 0.66 なら phase 2（sine 弾と burger 旋回が解禁）' do
      # 残り 50% に削る
      boss.damage(boss.max_hp / 2)
      expect(boss.phase).to be == 2
    end

    it 'ratio <= 0.33 なら phase 3（弁当 bounce 弾が解禁）' do
      boss.damage((boss.max_hp * 0.7).to_i)
      expect(boss.phase).to be == 3
    end
  end

  with '#tick（左右往復移動）' do
    it 'vx ぶん x が動く' do
      x0 = boss.x
      v  = boss.vx

      boss.tick

      expect(boss.x).to be == x0 + v
    end

    it '左壁に当たると vx が正方向に反転する' do
      # 壁を超えるように人為的に位置を動かす：
      # 内部状態を直接いじれないので tick を繰り返して左端に追い込む
      100.times { boss.instance_variable_set(:@x, -10.0); boss.tick }

      expect(boss.vx).to be > 0
      expect(boss.x).to be >= 0
    end

    it 'flash > 0 のとき tick で 1 ずつ減る（フラッシュ表示の寿命）' do
      boss.damage(10)   # flash = 3
      boss.tick
      expect(boss.flash).to be == 2
    end
  end
end
