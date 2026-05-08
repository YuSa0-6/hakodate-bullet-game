# frozen_string_literal: true

require_relative '../config'
require_relative '../assets'

# 敵弾（イカ墨）。サイン波・壁バウンド・お邪魔タイプを内包。
module Bullet
  module_function

  def update(b)
    if b[:sine]
      b[:phase] += 0.15
      b[:vx] = Math.sin(b[:phase]) * 3.0
    end
    if b[:bounce] && (b[:x] < 0 || b[:x] > Config::FIELD_W - Config::B_SIZE)
      b[:vx] *= -1
    end
    b[:x] += b[:vx] * Config::BULLET_SPEED
    b[:y] += b[:vy] * Config::BULLET_SPEED
  end

  def out?(b)
    b[:y] > Config::FIELD_H + 60 || b[:y] < -60 ||
      b[:x] < -120 || b[:x] > Config::FIELD_W + 120
  end

  # お邪魔弾の基底スプライト
  def garbage(x:, y:, vx:, vy:, sine: false, phase: 0.0)
    {
      type: Assets::Icons::BULLET_GARBAGE,
      x: x.to_f, y: y.to_f,
      vx: vx, vy: vy,
      sine: sine, phase: phase,
      garbage: true
    }
  end

  # 撃破した雑魚の種別ごとに違う弾幕パターンを生成。
  # x: warning が表示されていた水平位置（出現原点）
  # target_x, target_y: 受け手プレイヤーの自機座標（aimed 用）
  def attack_pattern(type, x, target_x:, target_y:)
    case type
    when :spread
      # 3-way 拡散（基本）
      [-0.3, 0.0, 0.3].map do |a|
        garbage(x: x, y: -Config::B_SIZE,
                vx: Math.sin(a) * 3.0, vy: Math.cos(a) * 3.5)
      end
    when :radial
      # 6発の放射（硬い敵を倒したら）
      6.times.map do |i|
        a = i * Math::PI * 2 / 6
        garbage(x: x, y: 40,
                vx: Math.cos(a) * 2.4, vy: Math.sin(a).abs * 2.4 + 1.4)
      end
    when :aimed
      # 自機狙い 3発の小スプレッド（素早い敵を倒したら）。30% homing 強化（旧 0.12）。
      angle = Math.atan2(target_y, target_x - x)
      sp = 4.0
      [-0.084, 0.0, 0.084].map do |off|
        a = angle + off
        garbage(x: x, y: -Config::B_SIZE,
                vx: Math.cos(a) * sp,
                vy: Math.sin(a).abs * sp + 1.2)
      end
    when :wave
      # サイン波 4発（コンボボーナスで送出）
      4.times.map do |i|
        garbage(x: x, y: -Config::B_SIZE - i * 24,
                vx: 0.0, vy: 2.4,
                sine: true, phase: rand * Math::PI * 2)
      end
    else
      [garbage(x: x, y: -Config::B_SIZE, vx: 0.0, vy: 3.5)]
    end
  end
end
