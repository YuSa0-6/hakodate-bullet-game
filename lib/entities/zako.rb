# frozen_string_literal: true

require_relative '../config'

# 雑魚敵（撃破でお邪魔チャージを稼ぐ）
module Zako
  module_function

  def spawn(type, x:, phase: 0.0)
    {
      emoji:       type[:emoji],
      x:           x.to_f,
      y:           -Config::ZAKO_SIZE.to_f,
      vy:          type[:vy],
      hp:          type[:hp],
      max_hp:      type[:hp],
      score:       type[:score],
      garbage:     type[:garbage],
      weave:       type[:weave],
      attack_type: type[:attack_type],
      phase:       phase,
      flash:       0
    }
  end

  def update(z)
    z[:phase] += 0.12
    z[:x] += Math.sin(z[:phase]) * 1.8 if z[:weave]
    z[:y] += z[:vy]
    z[:flash] -= 1 if z[:flash] > 0
  end

  def out?(z)
    z[:y] > Config::FIELD_H + Config::ZAKO_SIZE
  end
end
