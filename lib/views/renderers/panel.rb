# frozen_string_literal: true

require_relative '../../config'
require_relative '../../assets'
require_relative '../../sprites'

module Renderers
  # 1プレイヤーぶんのパネル（HUD + フィールド）
  # ── 描画コスト指針 ──
  # 1. 位置決めは transform: translate のみ（layout回避）
  # 2. サイズ・背景画像（ドット絵）は battle_view.rb の STATIC_CSS でクラス指定
  # 3. inline style には毎フレーム変わる transform / opacity / width のみ含める
  module Panel
    module_function

    PANEL_STYLE = ("width:#{Config::PANEL_W}px;height:#{Config::PANEL_H}px;" \
      'box-sizing:border-box;display:flex;flex-direction:column;' \
      'background:#0d0d1a;border:1px solid #1a1a2e;border-radius:6px;overflow:hidden;').freeze

    HUD_STYLE = ("height:#{Config::HUD_H}px;flex-shrink:0;" \
      'display:flex;align-items:center;justify-content:space-between;padding:0 10px;' \
      'background:#1a1a2e;color:white;font-family:sans-serif;font-size:12px;').freeze

    FIELD_STYLE = ("position:relative;width:#{Config::FIELD_W}px;height:#{Config::FIELD_H}px;" \
      'background:#0d0d1a;overflow:hidden;').freeze

    SP_PLAYER         = Sprites.class_name(:player)
    SP_SHOT           = Sprites.class_name(:shot)
    SP_BOSS_BODY      = Sprites.class_name(:boss_body)
    SP_BOSS_CROWN     = Sprites.class_name(:boss_crown)
    SP_BULLET_NORMAL  = Sprites.class_name(:bullet_normal)
    SP_BULLET_GARBAGE = Sprites.class_name(:bullet_garbage)
    SP_BULLET_STAR    = Sprites.class_name(:bullet_star)
    SP_WARNING        = Sprites.class_name(:warning)

    def call(builder, player:, side:)
      builder.tag(:div, style: PANEL_STYLE) do
        render_hud(builder, player)
        render_field(builder, player, side)
      end
    end

    def render_hud(builder, p)
      builder.tag(:div, style: HUD_STYLE) do
        builder.tag(:span, style: 'min-width:80px;') do
          builder.text(Assets::Icons::LIFE_FULL * p.lives + Assets::Icons::LIFE_EMPTY * (3 - p.lives))
        end
        builder.tag(:span, style: "color:#{p.color};font-weight:bold;font-size:13px;") do
          builder.text(p.name)
        end
        if p.combo > 1
          builder.tag(:span, style: 'color:#ffcc00;font-weight:bold;font-size:13px;') do
            builder.text("COMBO×#{p.combo}")
          end
        else
          builder.tag(:span) {}
        end
        builder.tag(:span, style: 'min-width:90px;text-align:right;color:#aaa;font-size:13px;') do
          builder.text("SCORE #{p.score}")
        end
      end
    end

    def render_field(builder, p, _side)
      builder.tag(:div, style: FIELD_STYLE) do
        render_boss_hpbar(builder, p) if p.boss
        render_warnings(builder, p)
        render_boss(builder, p)
        render_zakos(builder, p)
        render_foods(builder, p)
        render_bullets(builder, p)
        render_shots(builder, p)
        render_player(builder, p)
        render_dead_overlay(builder) unless p.alive?
      end
    end

    def render_boss_hpbar(builder, p)
      ratio = p.boss.hp_ratio
      builder.tag(:div, style: 'position:absolute;left:8px;right:8px;top:6px;height:6px;background:#2a0a0a;border:1px solid #5a1a1a;border-radius:3px;overflow:hidden;z-index:5;') do
        builder.tag(:div, style: "width:#{(ratio * 100).round(1)}%;height:100%;background:#f44;") {}
      end
    end

    # 上端の予告マーカー。opacity だけで残時間を表現（縦線・layout 変動なし）
    def render_warnings(builder, p)
      p.garbage_queue.warnings.each do |w|
        progress = 1.0 - (w[:frames_left].to_f / Config::GARBAGE_WARN_FRAMES)
        opacity  = 0.3 + 0.7 * progress
        builder.tag(:div, class: "warn ent #{SP_WARNING}",
                    style: "transform:translate(#{w[:x].to_i}px,12px);opacity:#{opacity.round(2)};") {}
      end
    end

    def render_boss(builder, p)
      return unless p.boss
      flash_cls = p.boss.flash > 0 ? ' flash' : ''
      builder.tag(:div, class: "bs ent#{flash_cls} #{SP_BOSS_BODY}",
                  style: "transform:translate(#{p.boss.x.to_i}px,#{p.boss.y.to_i}px);") {}
      builder.tag(:div, class: "crown ent #{SP_BOSS_CROWN}",
                  style: "transform:translate(#{(p.boss.x + Config::BOSS_W / 2 - 14).to_i}px,#{(p.boss.y - 18).to_i}px);") {}
    end

    def render_zakos(builder, p)
      p.zakos.each do |z|
        flash_cls = z[:flash] > 0 ? ' flash' : ''
        sprite    = Sprites::ZAKO_SPRITES.fetch(z[:emoji], :zako_octopus)
        x = z[:x].to_i
        y = z[:y].to_i
        builder.tag(:div, class: "z ent#{flash_cls} #{Sprites.class_name(sprite)}",
                    style: "transform:translate(#{x}px,#{y}px);") {}
        # 被弾時のみHPバー（layout コスト軽減）
        next unless z[:hp] < z[:max_hp]
        ratio = z[:hp].to_f / z[:max_hp]
        builder.tag(:div, class: 'hpbar', style: "transform:translate(#{x}px,#{y + Config::ZAKO_SIZE}px);") do
          builder.tag(:div, style: "width:#{(ratio * 100).round(1)}%;") {}
        end
      end
    end

    def render_foods(builder, p)
      p.foods.each do |f|
        sprite = Sprites::FOOD_SPRITES.fetch(f[:type], :food_squid)
        builder.tag(:div, class: "f ent #{Sprites.class_name(sprite)}",
                    style: "transform:translate(#{f[:x].to_i}px,#{f[:y].to_i}px);") {}
      end
    end

    def render_bullets(builder, p)
      p.bullets.each do |b|
        sp_cls = if b[:garbage]
                   SP_BULLET_GARBAGE
                 elsif b[:sprite] == :bullet_star
                   SP_BULLET_STAR
                 else
                   SP_BULLET_NORMAL
                 end
        builder.tag(:div, class: "b ent #{sp_cls}",
                    style: "transform:translate(#{b[:x].to_i}px,#{b[:y].to_i}px);") {}
      end
    end

    def render_shots(builder, p)
      color = p.color
      p.shots.each do |s|
        builder.tag(:div, class: "s ent #{SP_SHOT}",
                    style: "transform:translate(#{s[:x].to_i}px,#{s[:y].to_i}px);color:#{color};") {}
      end
    end

    def render_player(builder, p)
      pwr_cls = p.powered ? ' pwr' : ''
      # 無敵中は 6 frame 周期で点滅させる（プレイヤーが状態を視認できる）
      opacity = p.invuln_frames > 0 && (p.invuln_frames / 3).even? ? 0.35 : 1.0
      style = +"transform:translate(#{p.px.to_i}px,#{p.py.to_i}px);"
      style << "opacity:#{opacity};" if opacity != 1.0
      # .pl は -6px の margin で sprite 描画範囲を当たり判定より広めに見せる
      builder.tag(:div, class: "pl ent#{pwr_cls} #{SP_PLAYER}", style: style) {}
      hb_color = p.focus ? '#ff5577' : 'white'
      builder.tag(:div, class: 'hb', style: "position:absolute;background:#{hb_color};transform:translate(#{(p.px + 8).to_i}px,#{(p.py + 8).to_i}px);") {}
    end

    def render_dead_overlay(builder)
      builder.tag(:div, style: 'position:absolute;inset:0;background:rgba(0,0,0,0.6);display:flex;align-items:center;justify-content:center;font-size:48px;color:#f44;') do
        builder.text(Assets::Icons::DEAD)
      end
    end
  end
end
