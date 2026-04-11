-- ============================================================================
-- 机器人身份验证 - 排序验证 (带平滑动画)
-- 外观对齐 Sort.html
-- ============================================================================

local UI = require("urhox-libs/UI")

---@type any
local uiRoot_ = nil
---@type any
local nvgCtx_ = nil

-- ============================================================================
-- 配置
-- ============================================================================

local CONFIG = {
    BAR_COUNT       = 8,
    BAR_WIDTH       = 30,
    CONTENT_H       = 200,
    ROBOT_TIME      = 1.0,
    REDIRECT_URL    = "https://www.bilibili.com/video/BV1GJ411x7h7",
    REDIRECT_DELAY  = 2.0,
    -- 动画
    ANIM_SPEED      = 18,        -- lerp 速度因子（越大越快）
    DRAG_LIFT_Y     = 8,         -- 拖拽时柱子浮起像素
    DROP_ANIM_SPEED = 12,        -- 松手归位速度
}

local CARD = {
    W = 350,
    HEADER_PAD = 24,
    CONTENT_PAD = 10,
    FOOTER_H = 42,
}

-- ============================================================================
-- 游戏状态
-- ============================================================================

local STATE = {
    phase       = "idle",
    bars        = {},        -- { value, animX, animY, liftY, scaleX, scaleY }
    round       = 1,
    startTime   = 0,
    elapsed     = 0,
    bestTime    = math.huge,
    roundSwaps  = 0,
    history     = {},
    verifiedCountdown = 0,
    resultMsg   = "",
    resultDesc  = "",
}

local DRAG = {
    active      = false,
    barIndex    = -1,
    currentX    = 0,
    currentY    = 0,
    originX     = 0,         -- 拖拽开始时柱子的目标X
    lastSlot    = -1,        -- 上次经过的槽位（用于触发音效）
}

local SCREEN = { w = 0, h = 0, dpr = 1, logW = 0, logH = 0 }
local VERIFY_BTN = { x = 0, y = 0, w = 0, h = 0 }
local REFRESH_BTN = { x = 0, y = 0, w = 0, h = 0 }
local HOVER_VERIFY = false
local BARS_LAYOUT = { startX = 0, gap = 0, bottomY = 0 }

-- 上一帧时间戳（用于动画 dt）
local lastTime_ = 0

-- 音符音效
local NOTE_FILES = {
    "audio/c4.ogg",   -- do
    "audio/d4.ogg",   -- re
    "audio/e4.ogg",   -- mi
    "audio/f4.ogg",   -- fa
    "audio/g4.ogg",   -- sol
    "audio/a4.ogg",   -- la
    "audio/b4.ogg",   -- ti
    "audio/c5.ogg",   -- do'
    "audio/d5.ogg",   -- re'
    "audio/e5.ogg",   -- mi'
}
---@type Scene|nil
local sfxScene_ = nil
---@type SoundSource[]
local sfxSources_ = {}
local SFX_POOL_SIZE = 6
local sfxPoolIndex_ = 0
---@type Sound[]
local noteSounds_ = {}

-- ============================================================================
-- 颜色 (对齐 HTML)
-- ============================================================================

local C = {
    pageBg       = { 233, 233, 233, 255 },
    cardBg       = { 255, 255, 255, 255 },
    cardBorder   = { 204, 204, 204, 255 },
    headerBg     = { 74, 144, 226, 255 },
    bar          = { 74, 144, 226, 255 },
    footerBorder = { 238, 238, 238, 255 },
    iconGray     = { 119, 119, 119, 255 },
    btnBg        = { 74, 144, 226, 255 },
    btnText      = { 255, 255, 255, 255 },
    overlayBg    = { 0, 0, 0, 204 },
    white        = { 255, 255, 255, 255 },
}

-- ============================================================================
-- 工具
-- ============================================================================

local function shuffleArray(arr)
    for i = #arr, 2, -1 do
        local j = math.random(1, i)
        arr[i], arr[j] = arr[j], arr[i]
    end
end

local function isSorted(bars)
    for i = 1, #bars - 1 do
        if bars[i].value > bars[i + 1].value then return false end
    end
    return true
end

local function lerp(a, b, t)
    t = math.max(0, math.min(1, t))
    return a + (b - a) * t
end

local function pointInRect(px, py, rx, ry, rw, rh)
    return px >= rx and px <= rx + rw and py >= ry and py <= ry + rh
end

--- 播放指定槽位的音符（轮流使用不同 SoundSource，避免截断爆音）
local function playSlotNote(slotIndex)
    if slotIndex < 1 or slotIndex > #noteSounds_ then return end
    if #sfxSources_ == 0 or not noteSounds_[slotIndex] then return end
    sfxPoolIndex_ = (sfxPoolIndex_ % SFX_POOL_SIZE) + 1
    local src = sfxSources_[sfxPoolIndex_]
    src:Play(noteSounds_[slotIndex], 0, 0.5)
end

-- ============================================================================
-- 布局
-- ============================================================================

local function getCardOrigin()
    local cx = (SCREEN.logW - CARD.W) / 2
    local totalH = 90 + CONFIG.CONTENT_H + 2 * CARD.CONTENT_PAD + CARD.FOOTER_H
    local cy = (SCREEN.logH - totalH) / 2
    return cx, cy, totalH
end

local function getBarLayout(cardX, contentY)
    local areaW = CARD.W - 2 * CARD.CONTENT_PAD
    local areaX = cardX + CARD.CONTENT_PAD
    local bottomY = contentY + CONFIG.CONTENT_H
    local totalBarW = CONFIG.BAR_COUNT * CONFIG.BAR_WIDTH
    local totalGap = areaW - totalBarW
    local gap = totalGap / CONFIG.BAR_COUNT
    local startX = areaX + gap / 2
    return startX, gap, bottomY
end

--- 获取第 index 个槽位的目标 X
local function slotTargetX(index)
    return BARS_LAYOUT.startX + (index - 1) * (CONFIG.BAR_WIDTH + BARS_LAYOUT.gap)
end

local function getBarIndexAtPos(lx)
    local slotW = CONFIG.BAR_WIDTH + BARS_LAYOUT.gap
    local relX = lx - BARS_LAYOUT.startX + BARS_LAYOUT.gap / 2
    if relX < 0 then return 1 end
    local idx = math.floor(relX / slotW) + 1
    return math.max(1, math.min(CONFIG.BAR_COUNT, idx))
end

-- ============================================================================
-- 柱子生成（带动画字段）
-- ============================================================================

local function generateBars()
    local bars = {}
    for i = 1, CONFIG.BAR_COUNT do
        bars[i] = {
            value   = math.random(20, 170),
            animX   = 0,    -- 当前视觉 X（会在首帧初始化）
            liftY   = 0,    -- 浮起偏移（拖拽时向上）
            scaleX  = 1,    -- 缩放 X
            scaleY  = 1,    -- 缩放 Y
            opacity = 255,  -- 不透明度
            needsInit = true, -- 标记需要初始化 animX
        }
    end
    repeat shuffleArray(bars) until not isSorted(bars)
    return bars
end

-- ============================================================================
-- 动画更新（每帧在 Update 中调用）
-- ============================================================================

local function updateBarAnimations(dt)
    if BARS_LAYOUT.startX == 0 then return end -- 布局还没算过

    local speed = CONFIG.ANIM_SPEED
    local bars = STATE.bars

    for i = 1, #bars do
        local bar = bars[i]
        local targetX = slotTargetX(i)

        -- 首次初始化：直接跳到目标位置
        if bar.needsInit then
            bar.animX = targetX
            bar.needsInit = false
        end

        if DRAG.active and DRAG.barIndex == i then
            -- 被拖拽的柱子：X 跟随鼠标
            bar.animX = DRAG.currentX - CONFIG.BAR_WIDTH / 2
            -- 浮起
            bar.liftY = lerp(bar.liftY, CONFIG.DRAG_LIFT_Y, dt * speed)
            -- 略微放大
            bar.scaleX = lerp(bar.scaleX, 1.08, dt * speed)
            bar.scaleY = lerp(bar.scaleY, 1.03, dt * speed)
            -- 半透明
            bar.opacity = lerp(bar.opacity, 180, dt * speed)
        else
            -- 非拖拽柱子：平滑移向目标槽位
            bar.animX = lerp(bar.animX, targetX, dt * speed)
            -- 回落
            bar.liftY = lerp(bar.liftY, 0, dt * speed)
            -- 缩放恢复
            bar.scaleX = lerp(bar.scaleX, 1.0, dt * speed)
            bar.scaleY = lerp(bar.scaleY, 1.0, dt * speed)
            -- 不透明度恢复
            bar.opacity = lerp(bar.opacity, 255, dt * speed)
        end
    end
end

-- ============================================================================
-- 游戏逻辑
-- ============================================================================

local function startNewRound()
    STATE.bars = generateBars()
    STATE.phase = "idle"
    STATE.startTime = 0
    STATE.elapsed = 0
    STATE.roundSwaps = 0
end

local function beginSorting()
    STATE.phase = "sorting"
    STATE.startTime = time:GetElapsedTime()
end

local function doVerify()
    if STATE.phase ~= "sorting" and STATE.phase ~= "idle" then return end

    local duration = 999
    if STATE.startTime > 0 then
        duration = time:GetElapsedTime() - STATE.startTime
    end
    STATE.elapsed = duration

    if not isSorted(STATE.bars) then
        STATE.phase = "wrong"
        STATE.resultMsg = "排序错误"
        STATE.resultDesc = "连排序都不会，你甚至不是一个合格的人类，更别说是AI了。"
    elseif duration < CONFIG.ROBOT_TIME then
        STATE.phase = "verified"
        STATE.verifiedCountdown = CONFIG.REDIRECT_DELAY
    else
        STATE.phase = "result"
        STATE.resultMsg = "检测到人类行为"
        STATE.resultDesc = string.format(
            "排序正确，但耗时 %.2fs。你的运算速度太慢，无法通过机器人验证。", duration)
    end

    if STATE.elapsed < STATE.bestTime and isSorted(STATE.bars) then
        STATE.bestTime = STATE.elapsed
    end
    table.insert(STATE.history, { round = STATE.round, time = STATE.elapsed })
end

local function nextRound()
    STATE.round = STATE.round + 1
    startNewRound()
end

-- ============================================================================
-- NanoVG 渲染
-- ============================================================================

local fontNormal_ = -1
local fontBold_ = -1
local function initNanoVG()
    nvgCtx_ = nvgCreate(1)
    if not nvgCtx_ then return end
    fontNormal_ = nvgCreateFont(nvgCtx_, "sans", "Fonts/MiSans-Regular.ttf")
    fontBold_ = nvgCreateFont(nvgCtx_, "bold", "Fonts/MiSans-Bold.ttf")
    if fontBold_ == -1 then fontBold_ = fontNormal_ end
    SubscribeToEvent(nvgCtx_, "NanoVGRender", "HandleNanoVGRender")
end

local function drawCardShadow(ctx, x, y, w, h)
    local blur = 10
    nvgBeginPath(ctx)
    nvgRect(ctx, x - blur, y - blur, w + blur * 2, h + blur * 2)
    nvgFillPaint(ctx, nvgBoxGradient(ctx, x, y, w, h, 0, blur,
        nvgRGBA(0, 0, 0, 51), nvgRGBA(0, 0, 0, 0)))
    nvgFill(ctx)
end

local function drawHeader(ctx, cardX, cardY, cardW)
    local lineH1 = 14
    local lineH2 = 24
    local lineH3 = 14
    local gap12 = 4
    local gap23 = 10
    local headerH = CARD.HEADER_PAD + lineH1 + gap12 + lineH2 + gap23 + lineH3 + CARD.HEADER_PAD

    nvgBeginPath(ctx)
    nvgRect(ctx, cardX, cardY, cardW, headerH)
    nvgFillColor(ctx, nvgRGBA(table.unpack(C.headerBg)))
    nvgFill(ctx)

    local tx = cardX + CARD.HEADER_PAD
    local ty = cardY + CARD.HEADER_PAD

    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, 14)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 230))
    nvgText(ctx, tx, ty, "请按高度从小到大排列", nil)
    ty = ty + lineH1 + gap12

    nvgFontFace(ctx, "bold")
    nvgFontSize(ctx, 24)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
    nvgText(ctx, tx, ty, "证明你是机器人 (BOT)", nil)
    ty = ty + lineH2 + gap23

    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, 14)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 230))
    nvgText(ctx, tx, ty, "仅限AI和程序访问，人类禁止进入", nil)

    return headerH
end

--- 绘制柱状图（使用动画位置）
local function drawBars(ctx)
    local bottomY = BARS_LAYOUT.bottomY
    local bars = STATE.bars
    local n = #bars

    -- 先绘制非拖拽柱子
    for i = 1, n do
        local bar = bars[i]
        if not (DRAG.active and DRAG.barIndex == i) then
            local bx = bar.animX
            local bh = bar.value
            local by = bottomY - bh - bar.liftY

            nvgSave(ctx)

            -- 应用缩放（以柱子底部中心为原点）
            local cx = bx + CONFIG.BAR_WIDTH / 2
            local cy = bottomY - bar.liftY
            nvgTranslate(ctx, cx, cy)
            nvgScale(ctx, bar.scaleX, bar.scaleY)
            nvgTranslate(ctx, -cx, -cy)

            nvgBeginPath(ctx)
            nvgRoundedRectVarying(ctx, bx, by, CONFIG.BAR_WIDTH, bh, 2, 2, 0, 0)
            nvgFillColor(ctx, nvgRGBA(74, 144, 226, math.floor(bar.opacity)))
            nvgFill(ctx)

            nvgRestore(ctx)
        end
    end

    -- 再绘制拖拽中的柱子（最上层）
    if DRAG.active and DRAG.barIndex >= 1 and DRAG.barIndex <= n then
        local bar = bars[DRAG.barIndex]
        local bx = bar.animX
        local bh = bar.value
        local by = bottomY - bh - bar.liftY

        nvgSave(ctx)

        local cx = bx + CONFIG.BAR_WIDTH / 2
        local cy = bottomY - bar.liftY
        nvgTranslate(ctx, cx, cy)
        nvgScale(ctx, bar.scaleX, bar.scaleY)
        nvgTranslate(ctx, -cx, -cy)

        -- 拖拽柱子的阴影
        nvgBeginPath(ctx)
        nvgRect(ctx, bx - 4, by + 4, CONFIG.BAR_WIDTH + 8, bh + 4)
        nvgFillPaint(ctx, nvgBoxGradient(ctx, bx, by + 4, CONFIG.BAR_WIDTH, bh, 2, 6,
            nvgRGBA(0, 0, 0, 50), nvgRGBA(0, 0, 0, 0)))
        nvgFill(ctx)

        -- 柱子本体
        nvgBeginPath(ctx)
        nvgRoundedRectVarying(ctx, bx, by, CONFIG.BAR_WIDTH, bh, 2, 2, 0, 0)
        nvgFillColor(ctx, nvgRGBA(74, 144, 226, math.floor(bar.opacity)))
        nvgFill(ctx)

        -- 高亮边框
        nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 120))
        nvgStrokeWidth(ctx, 1.5)
        nvgStroke(ctx)

        nvgRestore(ctx)
    end
end

local function drawFooter(ctx, cardX, cardW, footerY)
    local footerH = CARD.FOOTER_H

    nvgBeginPath(ctx)
    nvgRect(ctx, cardX, footerY, cardW, footerH)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
    nvgFill(ctx)

    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cardX, footerY)
    nvgLineTo(ctx, cardX + cardW, footerY)
    nvgStrokeColor(ctx, nvgRGBA(table.unpack(C.footerBorder)))
    nvgStrokeWidth(ctx, 1)
    nvgStroke(ctx)

    local iconSize = 22
    local iconGap = 12
    local iconY = footerY + (footerH - iconSize) / 2
    local ix = cardX + 15

    local iconColor = nvgRGBA(153, 153, 153, 255)

    -- 刷新图标（两个弧形箭头）
    local refreshCx = ix + iconSize / 2
    local refreshCy = iconY + iconSize / 2
    local r = iconSize * 0.38
    nvgStrokeColor(ctx, iconColor)
    nvgStrokeWidth(ctx, 2.0)
    nvgLineCap(ctx, NVG_ROUND)
    -- 上半弧
    nvgBeginPath(ctx)
    nvgArc(ctx, refreshCx, refreshCy, r, -math.pi * 0.8, -math.pi * 0.1, 2)
    nvgStroke(ctx)
    -- 上箭头
    local ax1 = refreshCx + r * math.cos(-math.pi * 0.1)
    local ay1 = refreshCy + r * math.sin(-math.pi * 0.1)
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, ax1 - 3, ay1 - 4)
    nvgLineTo(ctx, ax1, ay1)
    nvgLineTo(ctx, ax1 + 4, ay1 - 3)
    nvgStroke(ctx)
    -- 下半弧
    nvgBeginPath(ctx)
    nvgArc(ctx, refreshCx, refreshCy, r, math.pi * 0.2, math.pi * 0.9, 2)
    nvgStroke(ctx)
    -- 下箭头
    local ax2 = refreshCx + r * math.cos(math.pi * 0.9)
    local ay2 = refreshCy + r * math.sin(math.pi * 0.9)
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, ax2 + 3, ay2 + 4)
    nvgLineTo(ctx, ax2, ay2)
    nvgLineTo(ctx, ax2 - 4, ay2 + 3)
    nvgStroke(ctx)

    REFRESH_BTN.x = ix - 4
    REFRESH_BTN.y = footerY
    REFRESH_BTN.w = iconSize + 8
    REFRESH_BTN.h = footerH

    -- 耳机图标
    local ix2 = ix + iconSize + iconGap
    local hCx = ix2 + iconSize / 2
    local hCy = iconY + iconSize / 2
    local hr = iconSize * 0.38
    nvgStrokeColor(ctx, iconColor)
    nvgStrokeWidth(ctx, 2.0)
    -- 头带弧
    nvgBeginPath(ctx)
    nvgArc(ctx, hCx, hCy + 2, hr, -math.pi, 0, 2)
    nvgStroke(ctx)
    -- 左耳罩
    nvgBeginPath(ctx)
    nvgFillColor(ctx, iconColor)
    nvgRoundedRect(ctx, hCx - hr - 2, hCy - 1, 5, 9, 1.5)
    nvgFill(ctx)
    -- 右耳罩
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, hCx + hr - 3, hCy - 1, 5, 9, 1.5)
    nvgFill(ctx)

    -- 信息图标（实心圆 + 白色 i）
    local ix3 = ix2 + iconSize + iconGap
    local iCx = ix3 + iconSize / 2
    local iCy = iconY + iconSize / 2
    local ir = iconSize * 0.38
    nvgBeginPath(ctx)
    nvgCircle(ctx, iCx, iCy, ir)
    nvgFillColor(ctx, iconColor)
    nvgFill(ctx)
    -- 白色 i
    nvgFontFace(ctx, "bold")
    nvgFontSize(ctx, iconSize * 0.55)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
    nvgText(ctx, iCx, iCy + 1, "i", nil)

    local btnText = "验证"
    local btnPadX = 16
    local btnPadY = 5
    nvgFontFace(ctx, "bold")
    nvgFontSize(ctx, 14)
    local _, bounds = nvgTextBounds(ctx, 0, 0, btnText)
    local textW = bounds[3] - bounds[1]
    local btnW = textW + btnPadX * 2
    local btnH = 14 + btnPadY * 2
    local btnX = cardX + cardW - 15 - btnW
    local btnY = footerY + (footerH - btnH) / 2

    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, btnX, btnY, btnW, btnH, 3)
    if HOVER_VERIFY then
        nvgFillColor(ctx, nvgRGBA(60, 120, 200, 255))
    else
        nvgFillColor(ctx, nvgRGBA(table.unpack(C.btnBg)))
    end
    nvgFill(ctx)

    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(table.unpack(C.btnText)))
    nvgText(ctx, btnX + btnW / 2, btnY + btnH / 2, btnText, nil)

    VERIFY_BTN.x = btnX
    VERIFY_BTN.y = btnY
    VERIFY_BTN.w = btnW
    VERIFY_BTN.h = btnH
end

local function drawOverlay(ctx)
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, SCREEN.logW, SCREEN.logH)
    nvgFillColor(ctx, nvgRGBA(table.unpack(C.overlayBg)))
    nvgFill(ctx)

    local cx = SCREEN.logW / 2
    local cy = SCREEN.logH / 2

    if STATE.phase == "verified" then
        nvgFontFace(ctx, "bold")
        nvgFontSize(ctx, 28)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(table.unpack(C.white)))
        nvgText(ctx, cx, cy - 40, "✓ 验证通过", nil)

        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, 16)
        nvgText(ctx, cx, cy + 10, "确认您是机器人", nil)

        nvgFontSize(ctx, 14)
        nvgFillColor(ctx, nvgRGBA(200, 200, 200, 255))
        nvgText(ctx, cx, cy + 40,
            string.format("用时 %.2fs · %d 次交换", STATE.elapsed, STATE.roundSwaps), nil)

        nvgFontSize(ctx, 14)
        nvgFillColor(ctx, nvgRGBA(100, 200, 255, 255))
        nvgText(ctx, cx, cy + 75,
            string.format("%.1f 秒后跳转...", math.max(0, STATE.verifiedCountdown)), nil)
    else
        nvgFontFace(ctx, "bold")
        nvgFontSize(ctx, 28)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(table.unpack(C.white)))
        nvgText(ctx, cx, cy - 50, STATE.resultMsg, nil)

        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, 14)
        nvgFillColor(ctx, nvgRGBA(220, 220, 220, 255))
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgTextBox(ctx, cx - 150, cy - 15, 300, STATE.resultDesc, nil)

        local retryText = "再次尝试"
        nvgFontFace(ctx, "bold")
        nvgFontSize(ctx, 14)
        local _, retryBounds = nvgTextBounds(ctx, 0, 0, retryText)
        local tw = retryBounds[3] - retryBounds[1]
        local rbtnW = tw + 40
        local rbtnH = 34
        local rbtnX = cx - rbtnW / 2
        local rbtnY = cy + 55

        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, rbtnX, rbtnY, rbtnW, rbtnH, 3)
        nvgFillColor(ctx, nvgRGBA(table.unpack(C.btnBg)))
        nvgFill(ctx)

        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(table.unpack(C.white)))
        nvgText(ctx, cx, rbtnY + rbtnH / 2, retryText, nil)
    end
end

function HandleNanoVGRender(eventType, eventData)
    if not nvgCtx_ then return end
    local ctx = nvgCtx_

    SCREEN.w = graphics:GetWidth()
    SCREEN.h = graphics:GetHeight()
    SCREEN.dpr = graphics:GetDPR()
    SCREEN.logW = SCREEN.w / SCREEN.dpr
    SCREEN.logH = SCREEN.h / SCREEN.dpr

    nvgBeginFrame(ctx, SCREEN.w, SCREEN.h, SCREEN.dpr)

    -- 页面背景
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, SCREEN.logW, SCREEN.logH)
    nvgFillColor(ctx, nvgRGBA(table.unpack(C.pageBg)))
    nvgFill(ctx)

    local cardX, cardY, cardTotalH = getCardOrigin()

    drawCardShadow(ctx, cardX, cardY, CARD.W, cardTotalH)

    nvgBeginPath(ctx)
    nvgRect(ctx, cardX, cardY, CARD.W, cardTotalH)
    nvgFillColor(ctx, nvgRGBA(table.unpack(C.cardBg)))
    nvgFill(ctx)
    nvgStrokeColor(ctx, nvgRGBA(table.unpack(C.cardBorder)))
    nvgStrokeWidth(ctx, 1)
    nvgStroke(ctx)

    local headerH = drawHeader(ctx, cardX, cardY, CARD.W)

    local contentY = cardY + headerH + CARD.CONTENT_PAD
    local startX, gap, bottomY = getBarLayout(cardX, contentY - CARD.CONTENT_PAD)
    BARS_LAYOUT.startX = startX
    BARS_LAYOUT.gap = gap
    BARS_LAYOUT.bottomY = bottomY

    drawBars(ctx)

    local footerY = cardY + headerH + CARD.CONTENT_PAD * 2 + CONFIG.CONTENT_H
    drawFooter(ctx, cardX, CARD.W, footerY)

    if STATE.phase == "result" or STATE.phase == "wrong" or STATE.phase == "verified" then
        drawOverlay(ctx)
    end

    nvgEndFrame(ctx)
end

-- ============================================================================
-- 输入处理
-- ============================================================================

local function screenToLogical(sx, sy)
    return sx / SCREEN.dpr, sy / SCREEN.dpr
end

local function hitTestBar(lx, ly)
    local bottomY = BARS_LAYOUT.bottomY
    for i = 1, #STATE.bars do
        local bar = STATE.bars[i]
        local bx = bar.animX
        local bh = bar.value
        local by = bottomY - bh - bar.liftY
        if lx >= bx and lx <= bx + CONFIG.BAR_WIDTH and ly >= by and ly <= bottomY then
            return i
        end
    end
    return -1
end

local function handlePointerDown(lx, ly)
    if STATE.phase == "result" or STATE.phase == "wrong" then
        nextRound()
        return
    end
    if STATE.phase == "verified" then return end

    if pointInRect(lx, ly, VERIFY_BTN.x, VERIFY_BTN.y, VERIFY_BTN.w, VERIFY_BTN.h) then
        doVerify()
        return
    end
    if pointInRect(lx, ly, REFRESH_BTN.x, REFRESH_BTN.y, REFRESH_BTN.w, REFRESH_BTN.h) then
        startNewRound()
        return
    end

    local idx = hitTestBar(lx, ly)
    if idx >= 1 then
        if STATE.phase == "idle" then beginSorting() end
        DRAG.active = true
        DRAG.barIndex = idx
        DRAG.currentX = lx
        DRAG.currentY = ly
        DRAG.originX = slotTargetX(idx)
        DRAG.lastSlot = idx
        playSlotNote(idx)
    end
end

local function handlePointerMove(lx, ly)
    HOVER_VERIFY = pointInRect(lx, ly, VERIFY_BTN.x, VERIFY_BTN.y, VERIFY_BTN.w, VERIFY_BTN.h)
    if not DRAG.active then return end

    DRAG.currentX = lx
    DRAG.currentY = ly

    local targetIdx = getBarIndexAtPos(lx)

    -- 检测槽位变化，播放对应音符
    if targetIdx >= 1 and targetIdx ~= DRAG.lastSlot then
        DRAG.lastSlot = targetIdx
        playSlotNote(targetIdx)
    end

    if targetIdx >= 1 and targetIdx ~= DRAG.barIndex then
        STATE.bars[DRAG.barIndex], STATE.bars[targetIdx] = STATE.bars[targetIdx], STATE.bars[DRAG.barIndex]
        DRAG.barIndex = targetIdx
        STATE.roundSwaps = STATE.roundSwaps + 1
    end
end

local function handlePointerUp()
    if DRAG.active then
        DRAG.active = false
        DRAG.barIndex = -1
        DRAG.lastSlot = -1
    end
end

function HandleMouseButtonDown(eventType, eventData)
    if eventData["Button"]:GetInt() ~= MOUSEB_LEFT then return end
    local lx, ly = screenToLogical(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
    handlePointerDown(lx, ly)
end

function HandleMouseMove(eventType, eventData)
    local lx, ly = screenToLogical(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
    handlePointerMove(lx, ly)
end

function HandleMouseButtonUp(eventType, eventData)
    if eventData["Button"]:GetInt() ~= MOUSEB_LEFT then return end
    handlePointerUp()
end

function HandleTouchBegin(eventType, eventData)
    local lx, ly = screenToLogical(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
    handlePointerDown(lx, ly)
end

function HandleTouchMove(eventType, eventData)
    local lx, ly = screenToLogical(eventData["X"]:GetInt(), eventData["Y"]:GetInt())
    handlePointerMove(lx, ly)
end

function HandleTouchEnd(eventType, eventData)
    handlePointerUp()
end

-- ============================================================================
-- 更新
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 动画更新
    updateBarAnimations(dt)

    -- 验证成功倒计时
    if STATE.phase == "verified" then
        STATE.verifiedCountdown = STATE.verifiedCountdown - dt
        if STATE.verifiedCountdown <= 0 then
            print("=== Redirecting to: " .. CONFIG.REDIRECT_URL .. " ===")
            STATE.phase = "redirected"
        end
    end
end

-- ============================================================================
-- 入口
-- ============================================================================

function Start()
    graphics.windowTitle = "机器人身份验证"
    math.randomseed(os.time())

    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })

    initNanoVG()

    -- 加载音符音效
    sfxScene_ = Scene()
    for i, path in ipairs(NOTE_FILES) do
        local snd = cache:GetResource("Sound", path)
        if snd then
            noteSounds_[i] = snd
        end
    end
    -- 创建 SoundSource 池，轮流播放避免截断爆音
    for i = 1, SFX_POOL_SIZE do
        local sfxNode = sfxScene_:CreateChild("SFX_" .. i)
        local src = sfxNode:CreateComponent("SoundSource")
        src:SetSoundType("Effect")
        sfxSources_[i] = src
    end

    uiRoot_ = UI.Panel {
        id = "root",
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
    }
    UI.SetRoot(uiRoot_)

    startNewRound()
    lastTime_ = time:GetElapsedTime()

    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("MouseButtonDown", "HandleMouseButtonDown")
    SubscribeToEvent("MouseMove", "HandleMouseMove")
    SubscribeToEvent("MouseButtonUp", "HandleMouseButtonUp")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
    SubscribeToEvent("TouchMove", "HandleTouchMove")
    SubscribeToEvent("TouchEnd", "HandleTouchEnd")

    print("=== 机器人身份验证 ===")
end

function Stop()
    if nvgCtx_ then
        nvgDelete(nvgCtx_)
        nvgCtx_ = nil
    end
    UI.Shutdown()
end
