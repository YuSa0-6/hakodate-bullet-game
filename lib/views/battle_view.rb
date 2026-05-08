# frozen_string_literal: true

require 'json'
require 'async'
require 'async/barrier'
require 'async/queue'
require 'async/clock'

require_relative '../config'
require_relative '../sprites'
require_relative '../game/battle'
require_relative 'renderers/panel'
require_relative 'renderers/center_gauge'
require_relative 'renderers/screens'

# Lively の View 本体。
# 状態管理（:start / :playing / :result）と Async ループだけを担う薄い層。
#
# Fiber 構成（playing 時）：
#   barrier 配下に
#     - tick_loop          : Clock 基準で固定タイムステップに張り付く描画ループ
#     - input_loop         : input_queue から消費して両 Player に dispatch
#     - 各 Player の food spawner（Player 内で起動）
#     - 各 Boss の main + bento パターン（Boss 内で起動）
#     - 各お邪魔警告（GarbageQueue#enqueue 時に1警告=1 fiber で起動）
#   barrier.stop で全 Fiber を一括停止できる（再戦・接続切断時のリーク防止）。
class BattleView < Live::View
  STATES = %i[start playing result].freeze

  HEAVY_ENTITY_THRESHOLD = 80
  HEAVY_FPS              = 24
  TICK_DT                = 1.0 / Config::FPS  # ゲーム時間は常に 30Hz 固定

  # KeyboardEvent.key 列。タイトル画面でこの並びを入力すると EXTRA が解放される。
  KONAMI_SEQUENCE = %w[ArrowUp ArrowUp ArrowDown ArrowDown
                       ArrowLeft ArrowRight ArrowLeft ArrowRight b a].freeze

  def initialize(...)
    super
    @state      = :start
    @difficulty = :easy
    @battle     = nil
    @barrier    = nil
    @input_queue = nil
    @extra_unlocked = false
    @konami_index   = 0
  end

  STATIC_CSS = <<~CSS
    /* ── 全画面スケール ── 固定座標(#{Config::W}x#{Config::H})を viewport にフィット */
    html, body { margin:0; padding:0; height:100%; background:#000; overflow:hidden; }
    live-view { display:block; width:100vw; height:100vh; position:relative; }
    .stage {
      width:#{Config::W}px; height:#{Config::H}px;
      position:absolute; left:0; top:0;
      transform-origin:0 0;
      transform: translate(var(--stage-tx, 0), var(--stage-ty, 0)) scale(var(--stage-scale, 1));
    }
    /* ── ドット絵共通：image-rendering:pixelated で輪郭をボケさせない ── */
    .ent { position:absolute; will-change:transform; image-rendering:pixelated; image-rendering:crisp-edges; }
    .b   { width:#{Config::B_SIZE}px; height:#{Config::B_SIZE}px; }
    .s   { width:#{Config::SHOT_SIZE}px; height:#{Config::SHOT_SIZE}px; filter:drop-shadow(0 0 3px currentColor); }
    .z   { width:#{Config::ZAKO_SIZE}px; height:#{Config::ZAKO_SIZE}px; }
    .z.flash { filter:drop-shadow(0 0 6px white); }
    .f   { width:#{Config::FOOD_SIZE}px; height:#{Config::FOOD_SIZE}px; filter:drop-shadow(0 0 4px #f0c040); }
    .pl  { width:#{Config::P_SIZE + 12}px; height:#{Config::P_SIZE + 12}px; margin:-6px 0 0 -6px; }
    .pl.pwr { filter:drop-shadow(0 0 6px #ff8c00) drop-shadow(0 0 10px #ffcc00); }
    .hb  { width:4px; height:4px; border-radius:50%; }
    .bs  { width:#{Config::BOSS_W}px; height:#{Config::BOSS_H}px; }
    .bs.flash { filter:drop-shadow(0 0 8px white) brightness(1.6); }
    .crown { width:28px; height:28px; }
    .warn  { width:24px; height:24px; }
    .hpbar { position:absolute;width:#{Config::ZAKO_SIZE}px;height:3px;background:#400; }
    .hpbar > div { height:100%;background:#f44; }

    /* ── ドット絵 sprite 群（各エンティティの背景画像） ── */
    #{Sprites.all_css}
  CSS

  RESIZE_JS = <<~JS.freeze
    (function() {
      if (window.__hakodateVsResize) return;
      window.__hakodateVsResize = true;
      var W = #{Config::W}, H = #{Config::H};
      function resize() {
        var s  = Math.min(window.innerWidth / W, window.innerHeight / H);
        var tx = (window.innerWidth  - W * s) / 2;
        var ty = (window.innerHeight - H * s) / 2;
        var st = document.documentElement.style;
        st.setProperty('--stage-scale', s);
        st.setProperty('--stage-tx', tx + 'px');
        st.setProperty('--stage-ty', ty + 'px');
      }
      window.addEventListener('resize', resize);
      resize();
    })();
  JS

  def bind(page)
    super
    script(<<~JS)
      if (!window.__hakodateVsKeys) {
        window.__hakodateVsKeys = true;
        var id = #{JSON.dump(@id)};
        document.addEventListener('keydown', function(e) {
          live.forward(id, {type: 'keydown', key: e.key, loc: e.location, repeat: e.repeat});
          if (['ArrowLeft','ArrowRight','ArrowUp','ArrowDown',' '].includes(e.key)) e.preventDefault();
        });
        document.addEventListener('keyup', function(e) {
          live.forward(id, {type: 'keyup', key: e.key, loc: e.location});
        });
      }
    JS
  end

  def close
    teardown_battle!
    super
  end

  # ── Event ──────────────────────────────────
  # playing 中はキーイベントを Async::Queue に流すだけ。実処理は input_loop が拾う。
  def handle(event)
    case @state
    when :start   then handle_title(event)
    when :playing then @input_queue&.enqueue(event)
    when :result  then handle_result(event)
    end
  end

  def handle_title(event)
    return unless event[:type] == 'keydown'
    return if event[:repeat]

    # Konami シーケンスが進行中で、入力が次に期待されるキーなら Konami が消費する
    # （難易度シフト・スタート判定はスキップ）。マッチに外れた入力は通常ハンドラに流す。
    return if consume_konami!(event[:key])

    case event[:key]
    when 'ArrowLeft', 'a', 'A'
      shift_difficulty(-1)
    when 'ArrowRight', 'd', 'D'
      shift_difficulty(+1)
    when 'Tab', 'F5', 'F12', 'Meta', 'Control', 'Alt', 'Shift', 'b', 'B'
      # b / B は Konami シーケンスの終端文字。中途半端なタイミングで押された
      # 場合に start_battle! へ流すと、ユーザーが Konami を入力しているつもりで
      # ゲームが始まってしまうため no-op にする（index 8 で押されたケースは
      # consume_konami! が先に true で吸収するので、ここには来ない）。
      nil
    else
      start_battle!
    end
  end

  # 一致したら true（呼び出し元はその入力の以後の処理を打ち切る）。
  # 外れたら false で返し、key 自体が先頭と一致するなら index=1 にリセット（連打耐性）。
  def consume_konami!(key)
    if key == KONAMI_SEQUENCE[@konami_index]
      @konami_index += 1
      if @konami_index >= KONAMI_SEQUENCE.size
        unlock_extra!
        @konami_index = 0
      end
      true
    else
      @konami_index = (key == KONAMI_SEQUENCE[0]) ? 1 : 0
      false
    end
  end

  def unlock_extra!
    return if @extra_unlocked
    @extra_unlocked = true
    @difficulty = Config::EXTRA_DIFFICULTY
    update!
  end

  def handle_result(event)
    return unless event[:type] == 'keydown'
    case event[:key]
    when 'r', 'R', 'Enter'
      start_battle!
    when 'Escape', 's', 'S'
      teardown_battle!
      @state = :start
      @battle = nil
      update!
    end
  end

  def shift_difficulty(delta)
    diffs = available_difficulties
    idx = (diffs.index(@difficulty) + delta) % diffs.size
    @difficulty = diffs[idx]
    update!
  end

  # @extra_unlocked のときだけ :extra を選択肢に含める
  def available_difficulties
    @extra_unlocked ? Config::ALL_DIFFICULTIES : Config::DIFFICULTIES
  end

  # ── Lifecycle ─────────────────────────────
  def start_battle!
    teardown_battle!

    @barrier     = Async::Barrier.new
    @input_queue = Async::Queue.new
    @battle      = Battle.new(difficulty: @difficulty, barrier: @barrier)
    @state       = :playing

    @barrier.async { |task| tick_loop(task) }
    @barrier.async { |task| input_loop(task) }
  end

  # 接続スコープの全 Fiber を停止。再戦時にも呼ぶ。
  def teardown_battle!
    @barrier&.stop
    @barrier = nil
    @input_queue = nil
  end

  # ── Loop ───────────────────────────────────
  # 「固定 game tick + 適応 render」モデル（Glenn Fiedler の "Fix Your Timestep!" の最小版）。
  #
  #   game tick (@battle.tick)        : 常に 30Hz 固定 = TICK_DT 毎
  #   render (update! → WebSocket 送信) : current_fps 毎（重い時 24Hz）
  #
  # こうすることで、ボスや GarbageQueue の Fiber が `task.sleep(FRAME_DT)` で
  # 数えている "ゲーム内時間" と、画面更新の頻度が **デカップル**される。
  # 過去：重い時に tick ごと 24Hz に落としていた → Fiber は 30fps tempo のまま走り、
  #       1 視覚フレームあたりの弾が増えて逆効果だった。
  def tick_loop(task)
    next_tick   = Async::Clock.now
    next_render = Async::Clock.now

    loop do
      @battle.tick

      if @battle.over?
        @state = :result
        update!
        break
      end

      now = Async::Clock.now
      if now >= next_render
        update!
        next_render = now + (1.0 / current_fps)
      end

      next_tick += TICK_DT
      delay = next_tick - Async::Clock.now
      if delay > 0
        task.sleep(delay)
      else
        # 大きく遅れたらキャッチアップを諦めて次刻みにリセット（spiral of death 回避）
        next_tick = Async::Clock.now
      end
    end
  end

  def input_loop(_task)
    loop do
      event = @input_queue.dequeue
      break if event.nil?
      @battle.dispatch_input(event)
    end
  end

  def current_fps
    return Config::FPS unless @battle
    total = @battle.p1.bullets.size + @battle.p1.zakos.size + @battle.p1.foods.size +
            @battle.p2.bullets.size + @battle.p2.zakos.size + @battle.p2.foods.size
    total > HEAVY_ENTITY_THRESHOLD ? HEAVY_FPS : Config::FPS
  end

  # ── Render ─────────────────────────────────
  def render(builder)
    builder.tag(:style) { builder.raw(STATIC_CSS) }
    builder.tag(:script) { builder.raw(RESIZE_JS) }
    builder.tag(:div, class: 'stage') do
      case @state
      when :start
        Renderers::Screens.title(builder, difficulty: @difficulty, extra_unlocked: @extra_unlocked)
      when :playing
        render_playing(builder)
      when :result
        Renderers::Screens.result(builder, battle: @battle)
      end
    end
  end

  def render_playing(builder)
    builder.tag(:div, style: stage_style) do
      Renderers::Panel.call(builder, player: @battle.p1, side: :left)
      Renderers::CenterGauge.call(builder, battle: @battle)
      Renderers::Panel.call(builder, player: @battle.p2, side: :right)
    end
  end

  def stage_style
    "display:flex;justify-content:center;align-items:flex-start;gap:#{Config::PANEL_GAP}px;" \
      "width:#{Config::W}px;height:#{Config::H}px;box-sizing:border-box;" \
      'background:linear-gradient(to bottom,#050510,#0d0d1a);font-family:sans-serif;user-select:none;'
  end
end
