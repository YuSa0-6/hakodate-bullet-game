# frozen_string_literal: true

require_relative '../lib/entities/player'
require_relative '../lib/assets'
require_relative 'helper'

# Player#tick 本体（衝突・移動・ホーミング・ライフ管理）の仕様。
# 既存 test/player.rb は撃破コンボ計算の純ロジックに集中しているため、
# こちらでは Async は絡めず、フィールド側の状態遷移を観察する。
describe Player do
  let(:barrier) { TestBarrier.new }
  let(:player) do
    p = Player.new(
      name: 'P1', color: '#7cf',
      controls: Config::P1_CONTROLS, diff: Config::DIFF[:easy],
      seed: 12_345
    )
    p.attach_barrier!(barrier)
    p
  end

  with '#move（フィールド境界クランプ）' do
    it '左へ進み続けても x は 0 を下回らない' do
      player.dx = -Config::P_SPEED
      300.times { player.tick(opponent_alive: true) }
      expect(player.px).to be == 0
    end

    it '右へ進み続けても x は FIELD_W - P_SIZE を超えない' do
      player.dx = Config::P_SPEED
      300.times { player.tick(opponent_alive: true) }
      expect(player.px).to be == (Config::FIELD_W - Config::P_SIZE).to_f
    end

    it 'focus 状態だと移動量は 40% に減る' do
      player.dx = Config::P_SPEED
      x0 = player.px
      player.focus = true
      player.tick(opponent_alive: true)
      moved = player.px - x0
      expect(moved).to be == Config::P_SPEED * 0.4
    end

    it '対角入力時の合成速度は P_SPEED と一致する（√2 倍バグの回帰防止）' do
      # フィールド中央寄りに置いて境界クランプの影響を消す
      player.px = 200.0
      player.py = 200.0
      player.dx = Config::P_SPEED
      player.dy = Config::P_SPEED
      x0 = player.px
      y0 = player.py
      player.tick(opponent_alive: true)

      moved = Math.hypot(player.px - x0, player.py - y0)
      expect(moved).to be_within(0.001).of(Config::P_SPEED.to_f)
    end

    it '対角入力 + focus でも合成速度は (P_SPEED * 0.4) と一致する' do
      player.px = 200.0
      player.py = 200.0
      player.focus = true
      player.dx = Config::P_SPEED
      player.dy = -Config::P_SPEED
      x0 = player.px
      y0 = player.py
      player.tick(opponent_alive: true)

      moved = Math.hypot(player.px - x0, player.py - y0)
      expect(moved).to be_within(0.001).of(Config::P_SPEED * 0.4)
    end
  end

  with '#tick（弾の inbox からのドレイン）' do
    it '@bullet_inbox に積まれた弾は次の tick 先頭で @bullets に取り込まれる' do
      bullet = {x: 10.0, y: 10.0, vx: 0.0, vy: 1.0, sine: false, bounce: false, garbage: true}
      player.instance_variable_get(:@bullet_inbox) << bullet
      expect(player.bullets).to be(:empty?)

      player.tick(opponent_alive: true)

      expect(player.bullets).to be(:include?, bullet)
    end

    it '@food_inbox に積まれた食べ物も同様に @foods へ取り込まれる' do
      food = {type: '🦑', x: 10.0, y: 10.0, vy: 1.0, phase: 0.0}
      player.instance_variable_get(:@food_inbox) << food

      player.tick(opponent_alive: true)

      expect(player.foods).to be(:include?, food)
    end
  end

  with '#tick（ショット自動発射）' do
    it 'frame % 4 == 0 のタイミングで自弾を生成する' do
      4.times { player.tick(opponent_alive: true) }
      expect(player.shots).not.to be(:empty?)
    end

    it 'powered 状態では 1発ではなく 3-way が出る' do
      # 通常状態の発射数を測る
      base_player = Player.new(
        name: 'P1', color: '#7cf',
        controls: Config::P1_CONTROLS, diff: Config::DIFF[:easy], seed: 1
      )
      base_player.attach_barrier!(TestBarrier.new)
      4.times { base_player.tick(opponent_alive: true) }
      normal_count = base_player.shots.size

      # powered 状態
      powered = Player.new(
        name: 'P2', color: '#7cf',
        controls: Config::P1_CONTROLS, diff: Config::DIFF[:easy], seed: 2
      )
      powered.attach_barrier!(TestBarrier.new)
      powered.instance_variable_set(:@powered, true)
      4.times { powered.tick(opponent_alive: true) }

      expect(powered.shots.size).to be == normal_count * 3
    end
  end

  with '#apply_bullet_homing（角速度クランプ）' do
    it 'speed が 0.01 未満の弾はスキップして向きを変えない' do
      b = {x: 100.0, y: 100.0, vx: 0.0, vy: 0.0, homing: {turn_rate: 0.1}}
      player.instance_variable_get(:@bullet_inbox) << b
      player.tick(opponent_alive: true)

      expect(b[:vx]).to be == 0.0
      expect(b[:vy]).to be == 0.0
    end

    it '速度を持つ弾は最大 turn_rate ラジアンだけ自機方向へ向きを回す（speed は保存）' do
      # 自機を画面中央付近に置く
      player.px = 200.0
      player.py = 400.0

      # 真上向きで右上に置いた弾。期待：自機方向（左下）へ徐々に向きが回る。
      b = {x: 300.0, y: 100.0, vx: 0.0, vy: -3.0, homing: {turn_rate: 0.05}}
      original_speed = Math.hypot(b[:vx], b[:vy])
      player.instance_variable_get(:@bullet_inbox) << b
      player.tick(opponent_alive: true)

      # speed は維持
      expect(Math.hypot(b[:vx], b[:vy])).to be_within(0.01).of(original_speed)
      # 自機が左下にいるので vy は減速（負→0方向へ）または vx が負へ
      expect(b[:vx] < 0 || b[:vy] > -3.0).to be == true
    end

    it '自機が弾の真後ろ（差分 ~ ±π）にいても角度差は [-π, π] に正規化される' do
      # 弾を画面真ん中、左方向に飛ばす（角 ~ π）。自機を右側に置くと差分は ~ -π 近辺。
      # while ループ実装でも modulo 実装でも、結果の turn は ±turn_rate に収まるべき。
      player.px = 400.0
      player.py = 300.0
      b = {x: 200.0, y: 300.0, vx: -3.0, vy: 0.0, homing: {turn_rate: 0.05}}
      original_speed = Math.hypot(b[:vx], b[:vy])
      player.instance_variable_get(:@bullet_inbox) << b
      player.tick(opponent_alive: true)

      expect(Math.hypot(b[:vx], b[:vy])).to be_within(0.01).of(original_speed)
      # 1 frame で ±turn_rate しか回らないので、向きはまだほぼ左向き
      angle = Math.atan2(b[:vy], b[:vx])
      expect(angle.abs).to be > (Math::PI - 0.1)
    end
  end

  with '#tick（ライフと alive）' do
    it '弾に当たると lives が 1 減って combo が 0 にリセットされる' do
      # 自機の中心付近に弾を直接置く（drain_inboxes 経由でフィールドへ）
      player.px = 100.0
      player.py = 100.0
      bullet = {
        x: player.px, y: player.py,
        vx: 0.0, vy: 0.0,
        sine: false, bounce: false, garbage: true
      }
      player.instance_variable_get(:@bullet_inbox) << bullet
      player.combo = 5

      player.tick(opponent_alive: true)

      expect(player.lives).to be == 2
      expect(player.combo).to be == 0
    end

    it 'lives が 0 になったら alive_state が false（出力 alive? も false）' do
      player.px = 100.0
      player.py = 100.0
      3.times do
        bullet = {
          x: player.px, y: player.py,
          vx: 0.0, vy: 0.0,
          sine: false, bounce: false, garbage: true
        }
        player.instance_variable_get(:@bullet_inbox) << bullet
        player.tick(opponent_alive: true)
        # 被弾後は無敵フレームが立つので、次の被弾までクールダウンする
        Player::INVULN_FRAMES.times { player.tick(opponent_alive: true) }
      end

      expect(player.lives).to be == 0
      expect(player).not.to be(:alive?)
    end

    it '被弾直後の連続ヒットは無敵時間で吸収される（INVULN_FRAMES 中はライフが減らない）' do
      player.px = 100.0
      player.py = 100.0
      bullet = {
        x: player.px, y: player.py,
        vx: 0.0, vy: 0.0,
        sine: false, bounce: false, garbage: true
      }
      player.instance_variable_get(:@bullet_inbox) << bullet
      player.tick(opponent_alive: true)

      lives_after_first = player.lives
      expect(lives_after_first).to be == 2
      expect(player.invuln_frames).to be > 0

      # 無敵中にもう 1 発重なって置いても lives は減らない
      bullet2 = {
        x: player.px, y: player.py,
        vx: 0.0, vy: 0.0,
        sine: false, bounce: false, garbage: true
      }
      player.instance_variable_get(:@bullet_inbox) << bullet2
      player.tick(opponent_alive: true)

      expect(player.lives).to be == lives_after_first
    end

    it '無敵時間が切れた次の被弾は通常通り lives を減らす' do
      player.px = 100.0
      player.py = 100.0
      player.instance_variable_get(:@bullet_inbox) << {
        x: player.px, y: player.py, vx: 0.0, vy: 0.0,
        sine: false, bounce: false, garbage: true
      }
      player.tick(opponent_alive: true)
      expect(player.lives).to be == 2

      # 無敵時間ぶん空 tick を回す
      Player::INVULN_FRAMES.times { player.tick(opponent_alive: true) }
      expect(player.invuln_frames).to be == 0

      player.instance_variable_get(:@bullet_inbox) << {
        x: player.px, y: player.py, vx: 0.0, vy: 0.0,
        sine: false, bounce: false, garbage: true
      }
      player.tick(opponent_alive: true)
      expect(player.lives).to be == 1
    end

    it 'alive? が false の tick は早期 return（frame は進まない）' do
      player.alive_state = false
      f0 = player.frame
      player.tick(opponent_alive: true)
      expect(player.frame).to be == f0
    end
  end

  with '#tick（食べ物取得）' do
    it '自機と重なる食べ物はピックアップされ、powered になり、@foods から消える' do
      player.px = 100.0
      player.py = 100.0
      food = {type: '🦑', x: player.px, y: player.py, vy: 0.0, phase: 0.0}
      player.instance_variable_get(:@food_inbox) << food

      player.tick(opponent_alive: true)

      expect(player.foods).to be(:empty?)
      expect(player.powered).to be == true
    end
  end

  with '#handle_event（入力 → dx/dy）' do
    it '左キー押下で dx が負になる' do
      player.handle_event(type: 'keydown', key: 'a')
      expect(player.dx).to be == -Config::P_SPEED
    end

    it '右キー離上で dx が 0 に戻る' do
      player.handle_event(type: 'keydown', key: 'd')
      player.handle_event(type: 'keyup', key: 'd')
      expect(player.dx).to be == 0
    end

    it 'P1 用 ShiftLeft（loc:1）で focus が立つ' do
      player.handle_event(type: 'keydown', key: 'Shift', loc: 1)
      expect(player.focus).to be == true
    end

    it 'P1 では ShiftRight（loc:2）は focus を立てない（P2 用）' do
      player.handle_event(type: 'keydown', key: 'Shift', loc: 2)
      expect(player.focus).to be == false
    end

    it '死亡中は入力を受け付けない' do
      player.alive_state = false
      player.handle_event(type: 'keydown', key: 'a')
      expect(player.dx).to be == 0
    end
  end

  with '#spawn_boss!（ボス生成）' do
    it '@boss が生成され、in_boss_phase? が true になる' do
      expect(player.in_boss_phase?).to be == false
      player.spawn_boss!
      expect(player.boss).not.to be_nil
      expect(player.in_boss_phase?).to be == true
    end
  end
end
