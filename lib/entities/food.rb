# frozen_string_literal: true

require_relative '../config'
require_relative '../assets'

# 落下グルメ（取得で 3秒間 3-WAY パワーアップ）
module Food
  module_function

  def spawn(rng:)
    type = Assets::FOODS.sample(random: rng)
    {
      type:  type[:emoji],
      x:     rng.rand(Config::FIELD_W - Config::FOOD_SIZE).to_f,
      y:     -Config::FOOD_SIZE.to_f,
      vy:    1.5,
      phase: rng.rand * Math::PI * 2
    }
  end

  def update(f)
    f[:phase] += 0.1
    f[:x] += Math.sin(f[:phase]) * 1.2
    f[:y] += f[:vy]
  end

  def out?(f)
    f[:y] > Config::FIELD_H + 60
  end
end
