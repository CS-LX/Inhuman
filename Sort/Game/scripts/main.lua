-- ============================================================================
-- 机器人身份验证 - 排序验证
-- 外观完全对齐 Sort.html
-- ============================================================================

local UI = require("urhox-libs/UI")

-- ============================================================================
-- 全局状态
-- ============================================================================

---@type any
local uiRoot_ = nil
---@type any
local nvgCtx_ = nil

-- 游戏配置 (对齐 HTML: 8 根柱子, 高度 20~170, 宽 30, gap 5)
local CONFIG = {
    BAR_COUNT       = 8,
    BAR_WIDTH       = 30,
    BAR_GAP         = 5,
    CONTENT_H       = 200,       -- HTML .content height: 200px
    ROBOT_TIME      = 1.0,
    REDIRECT_URL    = "https://www.bilibili.com/video/BV1GJ411x7h7",
    REDIRECT_DELAY  = 2.0,
}

-- 卡片布局常量 (对齐 HTML: width 350, 无圆角)
local CARD = {
    W = 350,
    HEADER_PAD = 24,       -- padding: 24px
    CONTENT_PAD = 10,      -- padding: 10px
    FOOTER_H = 42,         -- padding 10px + content ~22px
}

-- 游戏状态
local STATE = {
    phase       = "idle",        -- idle / sorting / result / verified / wrong
    bars        = {},            -- { value }
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

-- 拖拽状态
local DRAG = {
    active      = false,
    barIndex    = -1,
    currentX    = 0,
    currentY    = 0,
}

-- 屏幕信息
local SCREEN = { w = 0, h = 0, dpr = 1, logW = 0, logH = 0 }

-- 按钮热区 (运行时计算)
local VERIFY_BTN = { x = 0, y = 0, w = 0, h = 0 }
local REFRESH_BTN = { x = 0, y = 0, w = 0, h = 0 }
local HOVER_VERIFY = false
local HOVER_REFRESH = false

-- ============================================================================
-- 颜色方案 (精确对齐 HTML CSS)
-- ============================================================================
local C = {
    pageBg      = { 233, 233, 233, 255 },   -- #e9e9e9
    cardBg      = { 255, 255, 255, 255 },   -- white
    cardBorder  = { 204, 204, 204, 255 },   -- #ccc
    headerBg    = { 74, 144, 226, 255 },    -- #4A90E2
    bar         = { 74, 144, 226, 255 },    -- #4A90E2
    barDrag     = { 74, 144, 226, 128 },    -- opacity 0.5
    footerBorder= { 238, 238, 238, 255 },   -- #eee
    iconGray    = { 119, 119, 119, 255 },   -- #777
    btnBg       = { 74, 144, 226, 255 },    -- #4A90E2
    btnText     = { 255, 255, 255, 255 },
    overlayBg   = { 0, 0, 0, 204 },         -- rgba(0,0,0,0.8)
    white       = { 255, 255, 255, 255 },
    textDark    = { 50, 50, 50, 255 },
}

-- ============================================================================
-- 工具函数
-- ============================================================================

local function shuffleArray(arr)
    for i = #arr, 2, -1 do
        local j = math.random(1, i)
        arr[i], arr[j] = arr[j], arr[i]
    end
end

local function isSorted(bars)
    for i = 1, #bars - 1 do
        if bars[i].value > bars[i + 1].value then
            return false
        end
    end
    return true
end

local function generateBars()
    local bars = {}
    for i = 1, CONFIG.BAR_COUNT do
        bars[i] = {
            value = math.random(20, 170),  -- HTML: random 20~170
        }
    end
    -- 确保不是已排序
    repeat
        shuffleArray(bars)
    until not isSorted(bars)
    return bars
end

local function pointInRect(px, py, rx, ry, rw, rh)
    return px >= rx and px <= rx + rw and py >= ry and py <= ry + rh
end

-- ============================================================================
-- 布局计算 (运行时，基于卡片位置)
-- ============================================================================

--- 卡片左上角
local function getCardOrigin()
    local cx = (SCREEN.logW - CARD.W) / 2
    local totalH = 0 -- 动态算
    -- header ~= 24*2 + 三行文字高 ≈ 90
    -- content = 200 + 20 padding
    -- footer = 42
    totalH = 90 + CONFIG.CONTENT_H + 2 * CARD.CONTENT_PAD + CARD.FOOTER_H
    local cy = (SCREEN.logH - totalH) / 2
    return cx, cy, totalH
end

--- 柱状图区域（对齐 HTML: flex, space-around, align-items: flex-end）
--- space-around: 每个元素左右各留 equal space
local function getBarLayout(cardX, contentY)
    local areaW = CARD.W - 2 * CARD.CONTENT_PAD
    local areaX = cardX + CARD.CONTENT_PAD
    local bottomY = contentY + CONFIG.CONTENT_H

    -- space-around: 总间隔 = areaW - n*barW, 每个元素两侧间距 = gap/(n)
    local totalBarW = CONFIG.BAR_COUNT * CONFIG.BAR_WIDTH
    local totalGap = areaW - totalBarW
    local gap = totalGap / (CONFIG.BAR_COUNT)  -- space-around: 边距 = gap/2, 柱间 = gap
    local startX = areaX + gap / 2

    return startX, gap, bottomY
end

local function getBarX(startX, gap, index)
    return startX + (index - 1) * (CONFIG.BAR_WIDTH + gap)
end

local function getBarIndexAtPos(lx, startX, gap)
    local slotW = CONFIG.BAR_WIDTH + gap
    local relX = lx - startX + gap / 2
    if relX < 0 then return 1 end
    local idx = math.floor(relX / slotW) + 1
    return math.max(1, math.min(CONFIG.BAR_COUNT, idx))
end

-- 缓存当前帧的柱状图布局
local BARS_LAYOUT = { startX = 0, gap = 0, bottomY = 0, contentY = 0 }

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

    -- 如果还没开始过（idle），用时算 999
    local duration = 999
    if STATE.startTime > 0 then
        duration = time:GetElapsedTime() - STATE.startTime
    end
    STATE.elapsed = duration

    if not isSorted(STATE.bars) then
        -- 排序错误
        STATE.phase = "wrong"
        STATE.resultMsg = "排序错误"
        STATE.resultDesc = "连排序都不会，你甚至不是一个合格的人类，更别说是AI了。"
    elseif duration < CONFIG.ROBOT_TIME then
        -- 机器人
        STATE.phase = "verified"
        STATE.verifiedCountdown = CONFIG.REDIRECT_DELAY
    else
        -- 人类
        STATE.phase = "result"
        STATE.resultMsg = "检测到人类行为"
        STATE.resultDesc = string.format(
            "排序正确，但耗时 %.2fs。你的运算速度太慢，无法通过机器人验证。", duration)
    end

    if STATE.elapsed < STATE.bestTime and isSorted(STATE.bars) then
        STATE.bestTime = STATE.elapsed
    end
    table.insert(STATE.history, {
        round = STATE.round,
        time = STATE.elapsed,
    })
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
    if not nvgCtx_ then
        print("ERROR: Failed to create NanoVG context")
        return
    end
    fontNormal_ = nvgCreateFont(nvgCtx_, "sans", "Fonts/MiSans-Regular.ttf")
    fontBold_ = nvgCreateFont(nvgCtx_, "bold", "Fonts/MiSans-Bold.ttf")
    if fontBold_ == -1 then fontBold_ = fontNormal_ end

    SubscribeToEvent(nvgCtx_, "NanoVGRender", "HandleNanoVGRender")
end

--- 绘制卡片阴影 (HTML: box-shadow: 0 0 10px rgba(0,0,0,0.2))
local function drawCardShadow(ctx, x, y, w, h)
    local blur = 10
    nvgBeginPath(ctx)
    nvgRect(ctx, x - blur, y - blur, w + blur * 2, h + blur * 2)
    local sp = nvgBoxGradient(ctx, x, y, w, h, 0, blur,
        nvgRGBA(0, 0, 0, 51), nvgRGBA(0, 0, 0, 0))  -- 0.2*255≈51
    nvgFillPaint(ctx, sp)
    nvgFill(ctx)
end

--- 绘制头部 (对齐 HTML: 蓝色背景, padding 24, 左对齐文字)
local function drawHeader(ctx, cardX, cardY, cardW)
    -- 计算头部高度: padding-top 24 + 三行文字 + padding-bottom 24
    local lineH1 = 14  -- title-small font-size
    local lineH2 = 24  -- title-large font-size
    local lineH3 = 14
    local gap12 = 4    -- margin-bottom: 4px
    local gap23 = 10   -- margin-top: 10px
    local headerH = CARD.HEADER_PAD + lineH1 + gap12 + lineH2 + gap23 + lineH3 + CARD.HEADER_PAD

    -- 蓝色背景 (无圆角)
    nvgBeginPath(ctx)
    nvgRect(ctx, cardX, cardY, cardW, headerH)
    nvgFillColor(ctx, nvgRGBA(table.unpack(C.headerBg)))
    nvgFill(ctx)

    local tx = cardX + CARD.HEADER_PAD
    local ty = cardY + CARD.HEADER_PAD

    -- 行1: "请按高度从小到大排列" (14px, opacity 0.9)
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, 14)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 230))  -- 0.9
    nvgText(ctx, tx, ty, "请按高度从小到大排列", nil)
    ty = ty + lineH1 + gap12

    -- 行2: "证明你是机器人 (BOT)" (24px, bold)
    nvgFontFace(ctx, "bold")
    nvgFontSize(ctx, 24)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
    nvgText(ctx, tx, ty, "证明你是机器人 (BOT)", nil)
    ty = ty + lineH2 + gap23

    -- 行3: "仅限AI和程序访问，人类禁止进入" (14px, opacity 0.9)
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, 14)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 230))
    nvgText(ctx, tx, ty, "仅限AI和程序访问，人类禁止进入", nil)

    return headerH
end

--- 绘制柱状图 (对齐 HTML: 蓝色柱子 #4A90E2, 顶部圆角 2px, 无数值标签)
local function drawBars(ctx)
    local startX = BARS_LAYOUT.startX
    local gap = BARS_LAYOUT.gap
    local bottomY = BARS_LAYOUT.bottomY
    local bars = STATE.bars
    local n = #bars

    for i = 1, n do
        local bar = bars[i]
        local bx = getBarX(startX, gap, i)
        local bh = bar.value
        local by = bottomY - bh

        if DRAG.active and DRAG.barIndex == i then
            -- 拖拽中的柱子: opacity 0.5 (HTML .bar.dragging)
            nvgBeginPath(ctx)
            nvgRoundedRectVarying(ctx, bx, by, CONFIG.BAR_WIDTH, bh, 2, 2, 0, 0)
            nvgFillColor(ctx, nvgRGBA(74, 144, 226, 128))  -- 50% opacity
            nvgFill(ctx)
        else
            -- 正常柱子
            nvgBeginPath(ctx)
            nvgRoundedRectVarying(ctx, bx, by, CONFIG.BAR_WIDTH, bh, 2, 2, 0, 0)
            nvgFillColor(ctx, nvgRGBA(table.unpack(C.bar)))
            nvgFill(ctx)
        end
    end
end

--- 绘制底栏 (对齐 HTML: border-top #eee, 左侧 🔄🎧ⓘ, 右侧蓝色 "验证" 按钮)
local function drawFooter(ctx, cardX, cardW, footerY)
    local footerH = CARD.FOOTER_H

    -- 白色底栏背景
    nvgBeginPath(ctx)
    nvgRect(ctx, cardX, footerY, cardW, footerH)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
    nvgFill(ctx)

    -- 顶部分割线 #eee
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cardX, footerY)
    nvgLineTo(ctx, cardX + cardW, footerY)
    nvgStrokeColor(ctx, nvgRGBA(table.unpack(C.footerBorder)))
    nvgStrokeWidth(ctx, 1)
    nvgStroke(ctx)

    local iconY = footerY + footerH / 2
    local ix = cardX + 15

    -- 图标: 🔄 🎧 ⓘ (HTML: font-size 20, color #777, gap 15)
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, 20)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(table.unpack(C.iconGray)))

    -- 🔄 (刷新按钮 - 可点击)
    nvgText(ctx, ix, iconY, "🔄", nil)
    REFRESH_BTN.x = ix - 4
    REFRESH_BTN.y = footerY
    REFRESH_BTN.w = 28
    REFRESH_BTN.h = footerH

    nvgText(ctx, ix + 35, iconY, "🎧", nil)
    nvgText(ctx, ix + 70, iconY, "ⓘ", nil)

    -- 右侧: 蓝色 "验证" 按钮
    -- HTML: padding 10px 20px, font-weight bold, border-radius 3px, uppercase
    local btnText = "验证"
    local btnPadX = 20
    local btnPadY = 10
    nvgFontFace(ctx, "bold")
    nvgFontSize(ctx, 14)

    -- 测量文字宽度
    local bounds = {}
    nvgTextBounds(ctx, 0, 0, btnText, nil, bounds)
    local textW = bounds[3] - bounds[1]

    local btnW = textW + btnPadX * 2
    local btnH = 14 + btnPadY * 2
    local btnX = cardX + cardW - 15 - btnW
    local btnY = iconY - btnH / 2

    -- 按钮背景
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, btnX, btnY, btnW, btnH, 3)
    if HOVER_VERIFY then
        nvgFillColor(ctx, nvgRGBA(60, 120, 200, 255))  -- 悬停稍深
    else
        nvgFillColor(ctx, nvgRGBA(table.unpack(C.btnBg)))
    end
    nvgFill(ctx)

    -- 按钮文字
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(table.unpack(C.btnText)))
    nvgText(ctx, btnX + btnW / 2, btnY + btnH / 2, btnText, nil)

    -- 缓存按钮热区
    VERIFY_BTN.x = btnX
    VERIFY_BTN.y = btnY
    VERIFY_BTN.w = btnW
    VERIFY_BTN.h = btnH
end

--- 绘制结算遮罩 (对齐 HTML: 黑色 80% 遮罩, 白字, 居中, h2 + p + button)
local function drawOverlay(ctx)
    -- 全屏黑色遮罩 rgba(0,0,0,0.8)
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, SCREEN.logW, SCREEN.logH)
    nvgFillColor(ctx, nvgRGBA(table.unpack(C.overlayBg)))
    nvgFill(ctx)

    local cx = SCREEN.logW / 2
    local cy = SCREEN.logH / 2

    if STATE.phase == "verified" then
        -- 机器人验证通过 → 即将跳转
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
        -- "验证失败" 或 "排序错误" (对齐 HTML: h2 + p + button)
        -- h2 标题
        nvgFontFace(ctx, "bold")
        nvgFontSize(ctx, 28)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(table.unpack(C.white)))
        nvgText(ctx, cx, cy - 50, STATE.resultMsg, nil)

        -- p 描述 (可能很长，需要换行绘制)
        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, 14)
        nvgFillColor(ctx, nvgRGBA(220, 220, 220, 255))
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        -- 简单的手动分行（限宽 300px）
        nvgTextBox(ctx, cx - 150, cy - 15, 300, STATE.resultDesc, nil)

        -- "再次尝试" 按钮 (HTML: padding 10px 20px)
        local retryText = "再次尝试"
        nvgFontFace(ctx, "bold")
        nvgFontSize(ctx, 14)
        local bounds = {}
        nvgTextBounds(ctx, 0, 0, retryText, nil, bounds)
        local tw = bounds[3] - bounds[1]
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

--- 主渲染函数
function HandleNanoVGRender(eventType, eventData)
    if not nvgCtx_ then return end
    local ctx = nvgCtx_

    -- 更新屏幕
    SCREEN.w = graphics:GetWidth()
    SCREEN.h = graphics:GetHeight()
    SCREEN.dpr = graphics:GetDPR()
    SCREEN.logW = SCREEN.w / SCREEN.dpr
    SCREEN.logH = SCREEN.h / SCREEN.dpr

    nvgBeginFrame(ctx, SCREEN.w, SCREEN.h, SCREEN.dpr)

    local logW = SCREEN.logW
    local logH = SCREEN.logH

    -- 页面背景 #e9e9e9
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, logW, logH)
    nvgFillColor(ctx, nvgRGBA(table.unpack(C.pageBg)))
    nvgFill(ctx)

    -- 卡片
    local cardX, cardY, cardTotalH = getCardOrigin()

    -- 卡片阴影
    drawCardShadow(ctx, cardX, cardY, CARD.W, cardTotalH)

    -- 卡片白色背景 + 1px #ccc 边框 (无圆角)
    nvgBeginPath(ctx)
    nvgRect(ctx, cardX, cardY, CARD.W, cardTotalH)
    nvgFillColor(ctx, nvgRGBA(table.unpack(C.cardBg)))
    nvgFill(ctx)
    nvgStrokeColor(ctx, nvgRGBA(table.unpack(C.cardBorder)))
    nvgStrokeWidth(ctx, 1)
    nvgStroke(ctx)

    -- 头部
    local headerH = drawHeader(ctx, cardX, cardY, CARD.W)

    -- 内容区 (白色, padding 10, height 200)
    local contentY = cardY + headerH + CARD.CONTENT_PAD

    -- 计算柱状图布局并缓存
    local startX, gap, bottomY = getBarLayout(cardX, contentY - CARD.CONTENT_PAD)
    BARS_LAYOUT.startX = startX
    BARS_LAYOUT.gap = gap
    BARS_LAYOUT.bottomY = bottomY
    BARS_LAYOUT.contentY = contentY - CARD.CONTENT_PAD

    -- 绘制柱子
    drawBars(ctx)

    -- 底栏
    local footerY = cardY + headerH + CARD.CONTENT_PAD * 2 + CONFIG.CONTENT_H
    drawFooter(ctx, cardX, CARD.W, footerY)

    -- 结算遮罩
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

--- 判断点击是否在某个柱子上
local function hitTestBar(lx, ly)
    local startX = BARS_LAYOUT.startX
    local gap = BARS_LAYOUT.gap
    local bottomY = BARS_LAYOUT.bottomY

    for i = 1, #STATE.bars do
        local bx = getBarX(startX, gap, i)
        local bh = STATE.bars[i].value
        local by = bottomY - bh
        if lx >= bx and lx <= bx + CONFIG.BAR_WIDTH and ly >= by and ly <= bottomY then
            return i
        end
    end
    return -1
end

function HandleMouseButtonDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end

    local sx = eventData["X"]:GetInt()
    local sy = eventData["Y"]:GetInt()
    local lx, ly = screenToLogical(sx, sy)

    -- 结算页: 点击任意处 → 下一轮
    if STATE.phase == "result" or STATE.phase == "wrong" then
        nextRound()
        return
    end
    if STATE.phase == "verified" then return end

    -- 点击 "验证" 按钮
    if pointInRect(lx, ly, VERIFY_BTN.x, VERIFY_BTN.y, VERIFY_BTN.w, VERIFY_BTN.h) then
        doVerify()
        return
    end

    -- 点击 🔄 刷新按钮
    if pointInRect(lx, ly, REFRESH_BTN.x, REFRESH_BTN.y, REFRESH_BTN.w, REFRESH_BTN.h) then
        startNewRound()
        return
    end

    -- 点击柱子开始拖拽
    local idx = hitTestBar(lx, ly)
    if idx >= 1 then
        if STATE.phase == "idle" then
            beginSorting()
        end
        DRAG.active = true
        DRAG.barIndex = idx
        DRAG.currentX = lx
        DRAG.currentY = ly
    end
end

function HandleMouseMove(eventType, eventData)
    local sx = eventData["X"]:GetInt()
    local sy = eventData["Y"]:GetInt()
    local lx, ly = screenToLogical(sx, sy)

    -- 更新悬停状态
    HOVER_VERIFY = pointInRect(lx, ly, VERIFY_BTN.x, VERIFY_BTN.y, VERIFY_BTN.w, VERIFY_BTN.h)

    if not DRAG.active then return end

    DRAG.currentX = lx
    DRAG.currentY = ly

    -- 实时交换
    local targetIdx = getBarIndexAtPos(lx, BARS_LAYOUT.startX, BARS_LAYOUT.gap)
    if targetIdx >= 1 and targetIdx ~= DRAG.barIndex then
        STATE.bars[DRAG.barIndex], STATE.bars[targetIdx] = STATE.bars[targetIdx], STATE.bars[DRAG.barIndex]
        DRAG.barIndex = targetIdx
        STATE.roundSwaps = STATE.roundSwaps + 1
    end
end

function HandleMouseButtonUp(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end

    if DRAG.active then
        DRAG.active = false
        DRAG.barIndex = -1
    end
end

-- 触摸事件
function HandleTouchBegin(eventType, eventData)
    local sx = eventData["X"]:GetInt()
    local sy = eventData["Y"]:GetInt()
    local lx, ly = screenToLogical(sx, sy)

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
        if STATE.phase == "idle" then
            beginSorting()
        end
        DRAG.active = true
        DRAG.barIndex = idx
        DRAG.currentX = lx
        DRAG.currentY = ly
    end
end

function HandleTouchMove(eventType, eventData)
    if not DRAG.active then return end
    local sx = eventData["X"]:GetInt()
    local sy = eventData["Y"]:GetInt()
    local lx, ly = screenToLogical(sx, sy)
    DRAG.currentX = lx
    DRAG.currentY = ly

    local targetIdx = getBarIndexAtPos(lx, BARS_LAYOUT.startX, BARS_LAYOUT.gap)
    if targetIdx >= 1 and targetIdx ~= DRAG.barIndex then
        STATE.bars[DRAG.barIndex], STATE.bars[targetIdx] = STATE.bars[targetIdx], STATE.bars[DRAG.barIndex]
        DRAG.barIndex = targetIdx
        STATE.roundSwaps = STATE.roundSwaps + 1
    end
end

function HandleTouchEnd(eventType, eventData)
    if DRAG.active then
        DRAG.active = false
        DRAG.barIndex = -1
    end
end

-- ============================================================================
-- 更新
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    if STATE.phase == "verified" then
        STATE.verifiedCountdown = STATE.verifiedCountdown - dt
        if STATE.verifiedCountdown <= 0 then
            print("=== Redirecting to: " .. CONFIG.REDIRECT_URL .. " ===")
            -- 引擎无浏览器跳转 API，打印链接供外部处理
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

    uiRoot_ = UI.Panel {
        id = "root",
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
    }
    UI.SetRoot(uiRoot_)

    startNewRound()

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
