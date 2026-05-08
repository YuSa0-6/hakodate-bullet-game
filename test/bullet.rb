# frozen_string_literal: true

require_relative '../lib/entities/bullet'

# 弾 (Bullet) モジュールの仕様。
#
# update / out? は副作用つきの「自走」ロジック、
# attack_pattern は撃破した雑魚の種類ごとに違うお邪魔弾幕を生成する純関数。
describe Bullet do
  with '.update（位置の自走）' do
    it 'vx, vy ぶん x, y を進める（BULLET_SPEED で減速）' do
      b = {x: 100.0, y: 50.0, vx: 2.0, vy: 3.0}

      Bullet.update(b)

      expect(b[:x]).to be == 100.0 + 2.0 * Config::BULLET_SPEED
      expect(b[:y]).to be == 50.0 + 3.0 * Config::BULLET_SPEED
    end

    it ':sine が真なら phase が進み vx は sin 波に置き換わる' do
      b = {x: 100.0, y: 50.0, vx: 5.0, vy: 1.0, sine: true, phase: 0.0}

      Bullet.update(b)

      expect(b[:phase]).to be == 0.15
      expect(b[:vx]).to be == Math.sin(0.15) * 3.0
    end

    it ':bounce が真で壁にぶつかると vx が反転する' do
      b = {x: -1.0, y: 50.0, vx: 2.0, vy: 1.0, bounce: true}

      Bullet.update(b)

      expect(b[:vx]).to be < 0
    end
  end

  with '.out?（画面外判定）' do
    it 'フィールド下方に大きく外れたら true' do
      expect(Bullet.out?({x: 100, y: Config::FIELD_H + 100})).to be == true
    end

    it 'フィールド内なら false' do
      expect(Bullet.out?({x: 100, y: 100})).to be == false
    end
  end

  with '.attack_pattern（雑魚撃破による弾幕パターン）' do
    let(:target_x) { 250.0 }
    let(:target_y) { 600.0 }

    with ':spread（基本）' do
      it '3-way の拡散弾を生成する' do
        bullets = Bullet.attack_pattern(:spread, 100.0, target_x: target_x, target_y: target_y)

        expect(bullets.size).to be == 3
        expect(bullets).to be(:all?) { |b| b[:garbage] == true }
      end

      it '生成された弾は下向き（vy > 0）' do
        bullets = Bullet.attack_pattern(:spread, 100.0, target_x: target_x, target_y: target_y)

        expect(bullets).to be(:all?) { |b| b[:vy] > 0 }
      end
    end

    with ':radial（硬い敵の放射）' do
      it '6発の放射弾を生成する' do
        bullets = Bullet.attack_pattern(:radial, 100.0, target_x: target_x, target_y: target_y)

        expect(bullets.size).to be == 6
      end
    end

    with ':aimed（自機狙い）' do
      it '受け手の自機方向に 3発、小スプレッドで撃つ' do
        bullets = Bullet.attack_pattern(:aimed, 100.0, target_x: target_x, target_y: target_y)

        expect(bullets.size).to be == 3
        # target_x が原点より右なので、中央弾の vx は正方向
        expect(bullets[1][:vx]).to be > 0
      end

      it 'target_x が原点より左なら中央弾の vx は負方向' do
        bullets = Bullet.attack_pattern(:aimed, 500.0, target_x: 50.0, target_y: target_y)

        expect(bullets[1][:vx]).to be < 0
      end
    end

    with ':wave（コンボボーナスのサイン波）' do
      it '4発の :sine 弾を縦並びで生成する' do
        bullets = Bullet.attack_pattern(:wave, 100.0, target_x: target_x, target_y: target_y)

        expect(bullets.size).to be == 4
        expect(bullets).to be(:all?) { |b| b[:sine] == true }
        # 縦並びなので y は単調減（負方向にずれる）
        ys = bullets.map { |b| b[:y] }
        expect(ys).to be == ys.sort.reverse
      end
    end

    it '未知の型は安全に 1発のフォールバック弾を返す' do
      bullets = Bullet.attack_pattern(:unknown_type, 100.0, target_x: target_x, target_y: target_y)

      expect(bullets.size).to be == 1
      expect(bullets.first[:garbage]).to be == true
    end
  end
end
