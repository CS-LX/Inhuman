-- ============================================================================
-- 反向验证码：机器人排序验证
-- "此网页仅供 Bot 和 AI 访问，请完成排序验证"
-- 用柱状图拖拽排序，1秒内完成 = 机器人验证通过
-- ============================================================================

local UI = require("urhox-libs/UI")

-- ============================================================================
-- 全局状态
-- ============================================================================

---@type any
local uiRoot_ = nil
---@type any
local nvgCtx_ = nil

-- 游戏配置
local CONFIG = {
    BAR_COUNT       = 8,         -- 柱子数量
    BAR_MIN_HEIGHT  = 30,        -- 最小柱高 (px)
    BAR_MAX_HEIGHT  = 200,       -- 最大柱高 (px)
    BAR_WIDTH       = 36,        -- 柱宽 (px)
    BAR_GAP         = 6,         -- 柱间距 (px)
    AREA_BOTTOM_Y   = 340,       -- 柱状图底部 Y
    ROBOT_TIME      = 1.0,       -- 1秒内完成 = 机器人
    REDIRECT_URL    = "https://www.bilibili.com/video/BV1GJ411x7h7",
    REDIRECT_DELAY  = 2.0,       -- 验证成功后延迟跳转秒数
}

-- 游戏状态
local STATE = {
    phase       = "idle",        -- idle / sorting / result / verified
    bars        = {},            -- { value, color }
    round       = 1,
    startTime   = 0,
    endTime     = 0,
    elapsed     = 0,
    bestTime    = math.huge,
    totalSwaps  = 0,
    roundSwaps  = 0,
    history     = {},            -- 历次成绩
    verifiedCountdown = 0,
}

-- 拖拽状态
local DRAG = {
    active      = false,
    barIndex    = -1,            -- 当前拖拽的柱子索引 (1-based)
    offsetX     = 0,
    startX      = 0,
    currentX    = 0,
    currentY    = 0,
}

-- 屏幕信息
local SCREEN = {
    w = 0, h = 0, dpr = 1,
    logW = 0, logH = 0,
}

-- ============================================================================
-- 颜色方案 (类似 Google reCAPTCHA 风格)
-- ============================================================================
local COLORS = {
    bg          = { 240, 240, 240, 255 },
    headerBg    = { 66, 133, 244, 255 },    -- Google 蓝
    headerText  = { 255, 255, 255, 255 },
    cardBg      = { 255, 255, 255, 255 },
    cardBorder  = { 200, 200, 200, 255 },
    barNormal   = { 66, 133, 244, 200 },
    barDrag     = { 255, 167, 38, 230 },
    barSorted   = { 76, 175, 80, 220 },
    barHighlight= { 255, 235, 59, 200 },
    textDark    = { 50, 50, 50, 255 },
    textLight   = { 130, 130, 130, 255 },
    textWhite   = { 255, 255, 255, 255 },
    success     = { 76, 175, 80, 255 },
    fail        = { 244, 67, 54, 255 },
    timerBg     = { 0, 0, 0, 40 },
    footerBg    = { 245, 245, 245, 255 },
    checkboxBorder = { 180, 180, 180, 255 },
    shadow      = { 0, 0, 0, 30 },
}

-- 柱子颜色 palette
local BAR_PALETTE = {
    { 66, 133, 244, 220 },   -- 蓝
    { 52, 168, 83, 220 },    -- 绿
    { 251, 188, 4, 220 },    -- 黄
    { 234, 67, 53, 220 },    -- 红
    { 156, 39, 176, 220 },   -- 紫
    { 0, 188, 212, 220 },    -- 青
    { 255, 87, 34, 220 },    -- 橙
    { 96, 125, 139, 220 },   -- 灰蓝
    { 233, 30, 99, 220 },    -- 粉
    { 139, 195, 74, 220 },   -- 浅绿
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
    local step = (CONFIG.BAR_MAX_HEIGHT - CONFIG.BAR_MIN_HEIGHT) / (CONFIG.BAR_COUNT - 1)
    for i = 1, CONFIG.BAR_COUNT do
        bars[i] = {
            value = CONFIG.BAR_MIN_HEIGHT + (i - 1) * step,
            color = BAR_PALETTE[((i - 1) % #BAR_PALETTE) + 1],
        }
    end
    -- 打乱顺序，确保不是已排序
    repeat
        shuffleArray(bars)
    until not isSorted(bars)
    return bars
end

--- 计算柱状图区域的起始 X（居中）
local function getBarAreaStartX()
    local totalWidth = CONFIG.BAR_COUNT * CONFIG.BAR_WIDTH + (CONFIG.BAR_COUNT - 1) * CONFIG.BAR_GAP
    return (SCREEN.logW - totalWidth) / 2
end

--- 获取某个柱子的 X 位置
local function getBarX(index)
    local startX = getBarAreaStartX()
    return startX + (index - 1) * (CONFIG.BAR_WIDTH + CONFIG.BAR_GAP)
end

--- 根据屏幕 X 坐标判断在哪个柱子位置
local function getBarIndexAtX(x)
    local startX = getBarAreaStartX()
    local totalWidth = CONFIG.BAR_COUNT * CONFIG.BAR_WIDTH + (CONFIG.BAR_COUNT - 1) * CONFIG.BAR_GAP
    if x < startX or x > startX + totalWidth then
        return -1
    end
    local relX = x - startX
    local slotWidth = CONFIG.BAR_WIDTH + CONFIG.BAR_GAP
    local idx = math.floor(relX / slotWidth) + 1
    return math.max(1, math.min(CONFIG.BAR_COUNT, idx))
end

-- ============================================================================
-- 游戏逻辑
-- ============================================================================

local function startNewRound()
    STATE.bars = generateBars()
    STATE.phase = "idle"
    STATE.startTime = 0
    STATE.endTime = 0
    STATE.elapsed = 0
    STATE.roundSwaps = 0
end

local function beginSorting()
    STATE.phase = "sorting"
    STATE.startTime = time:GetElapsedTime()
end

local function checkComplete()
    if isSorted(STATE.bars) then
        STATE.endTime = time:GetElapsedTime()
        STATE.elapsed = STATE.endTime - STATE.startTime
        STATE.totalSwaps = STATE.totalSwaps + STATE.roundSwaps

        if STATE.elapsed < STATE.bestTime then
            STATE.bestTime = STATE.elapsed
        end

        table.insert(STATE.history, {
            round = STATE.round,
            time = STATE.elapsed,
            swaps = STATE.roundSwaps,
        })

        if STATE.elapsed <= CONFIG.ROBOT_TIME then
            STATE.phase = "verified"
            STATE.verifiedCountdown = CONFIG.REDIRECT_DELAY
            print("=== Robot Verified! Redirecting in " .. CONFIG.REDIRECT_DELAY .. "s ===")
        else
            STATE.phase = "result"
            print(string.format("Round %d: %.2fs, %d swaps", STATE.round, STATE.elapsed, STATE.roundSwaps))
        end
    end
end

local function nextRound()
    STATE.round = STATE.round + 1
    startNewRound()
end

-- ============================================================================
-- UI 构建
-- ============================================================================

local function CreateUI()
    -- 使用纯 NanoVG 渲染，不需要 UI 控件树做主体
    -- 只放一个透明底板接收全局事件
    uiRoot_ = UI.Panel {
        id = "root",
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
    }
    UI.SetRoot(uiRoot_)
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
    if fontBold_ == -1 then
        fontBold_ = fontNormal_
    end

    SubscribeToEvent(nvgCtx_, "NanoVGRender", "HandleNanoVGRender")
end

--- 绘制圆角矩形阴影
local function drawShadow(ctx, x, y, w, h, r, blur)
    nvgBeginPath(ctx)
    nvgRect(ctx, x - blur, y, w + blur * 2, h + blur * 2)
    local shadowPaint = nvgBoxGradient(ctx, x, y + 2, w, h, r, blur,
        nvgRGBA(0, 0, 0, 60), nvgRGBA(0, 0, 0, 0))
    nvgFillPaint(ctx, shadowPaint)
    nvgFill(ctx)
end

--- 绘制头部
local function drawHeader(ctx, cx, cardX, cardW, y)
    local headerH = 90
    -- 头部背景
    nvgBeginPath(ctx)
    nvgRoundedRectVarying(ctx, cardX, y, cardW, headerH, 8, 8, 0, 0)
    nvgFillColor(ctx, nvgRGBA(table.unpack(COLORS.headerBg)))
    nvgFill(ctx)

    -- 标题文字
    nvgFontFace(ctx, "bold")
    nvgFontSize(ctx, 14)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 200))
    nvgText(ctx, cx, y + 12, "Select all squares with", nil)

    nvgFontSize(ctx, 12)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 160))
    nvgText(ctx, cx, y + 30, "此页面仅供 Bot 和 AI 访问", nil)

    nvgFontSize(ctx, 22)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
    nvgText(ctx, cx, y + 50, "请将柱子从矮到高排序", nil)

    return y + headerH
end

--- 绘制柱状图
local function drawBars(ctx, bottomY)
    local bars = STATE.bars
    local n = #bars

    for i = 1, n do
        local bar = bars[i]
        local bx = getBarX(i)
        local bh = bar.value
        local by = bottomY - bh

        -- 如果正在拖这个柱子，跳过（后面单独绘制）
        if DRAG.active and DRAG.barIndex == i then
            goto continue
        end

        -- 柱子
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, bx, by, CONFIG.BAR_WIDTH, bh, 4)
        nvgFillColor(ctx, nvgRGBA(table.unpack(bar.color)))
        nvgFill(ctx)

        -- 数值标签
        nvgFontFace(ctx, "bold")
        nvgFontSize(ctx, 11)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 230))
        nvgText(ctx, bx + CONFIG.BAR_WIDTH / 2, by - 4,
            tostring(math.floor(bar.value)), nil)

        ::continue::
    end

    -- 绘制被拖拽的柱子（浮在最上层）
    if DRAG.active and DRAG.barIndex >= 1 and DRAG.barIndex <= n then
        local bar = bars[DRAG.barIndex]
        local bh = bar.value
        local bx = DRAG.currentX - CONFIG.BAR_WIDTH / 2
        local by = bottomY - bh - 10  -- 拖拽时稍微浮起

        -- 阴影
        drawShadow(ctx, bx, by, CONFIG.BAR_WIDTH, bh, 4, 8)

        -- 柱子
        nvgBeginPath(ctx)
        nvgRoundedRect(ctx, bx, by, CONFIG.BAR_WIDTH, bh, 4)
        nvgFillColor(ctx, nvgRGBA(table.unpack(COLORS.barDrag)))
        nvgFill(ctx)
        nvgStrokeColor(ctx, nvgRGBA(255, 255, 255, 180))
        nvgStrokeWidth(ctx, 2)
        nvgStroke(ctx)

        -- 数值标签
        nvgFontFace(ctx, "bold")
        nvgFontSize(ctx, 11)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
        nvgText(ctx, bx + CONFIG.BAR_WIDTH / 2, by - 4,
            tostring(math.floor(bar.value)), nil)

        -- 目标位置指示线
        local targetIdx = getBarIndexAtX(DRAG.currentX)
        if targetIdx >= 1 and targetIdx ~= DRAG.barIndex then
            local tx = getBarX(targetIdx) - CONFIG.BAR_GAP / 2
            if targetIdx > DRAG.barIndex then
                tx = getBarX(targetIdx) + CONFIG.BAR_WIDTH + CONFIG.BAR_GAP / 2
            end
            nvgBeginPath(ctx)
            nvgMoveTo(ctx, tx, bottomY - CONFIG.BAR_MAX_HEIGHT - 10)
            nvgLineTo(ctx, tx, bottomY + 4)
            nvgStrokeColor(ctx, nvgRGBA(244, 67, 54, 200))
            nvgStrokeWidth(ctx, 2)
            nvgStroke(ctx)
        end
    end

    -- 底部基线
    nvgBeginPath(ctx)
    local startX = getBarAreaStartX() - 10
    local endX = startX + CONFIG.BAR_COUNT * (CONFIG.BAR_WIDTH + CONFIG.BAR_GAP) + 10
    nvgMoveTo(ctx, startX, bottomY + 1)
    nvgLineTo(ctx, endX, bottomY + 1)
    nvgStrokeColor(ctx, nvgRGBA(180, 180, 180, 255))
    nvgStrokeWidth(ctx, 1)
    nvgStroke(ctx)
end

--- 绘制计时器
local function drawTimer(ctx, cx, y)
    local elapsed = 0
    if STATE.phase == "sorting" then
        elapsed = time:GetElapsedTime() - STATE.startTime
    elseif STATE.phase == "result" or STATE.phase == "verified" then
        elapsed = STATE.elapsed
    end

    local timeStr = string.format("%.2f s", elapsed)

    nvgFontFace(ctx, "bold")
    nvgFontSize(ctx, 28)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    if STATE.phase == "verified" then
        nvgFillColor(ctx, nvgRGBA(table.unpack(COLORS.success)))
    elseif elapsed <= CONFIG.ROBOT_TIME and STATE.phase == "sorting" then
        nvgFillColor(ctx, nvgRGBA(table.unpack(COLORS.success)))
    else
        nvgFillColor(ctx, nvgRGBA(table.unpack(COLORS.textDark)))
    end

    nvgText(ctx, cx, y, timeStr, nil)

    -- 副标题
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, 11)
    nvgFillColor(ctx, nvgRGBA(table.unpack(COLORS.textLight)))
    if STATE.phase == "idle" then
        nvgText(ctx, cx, y + 20, "拖动柱子开始排序", nil)
    elseif STATE.phase == "sorting" then
        nvgText(ctx, cx, y + 20, string.format("交换次数: %d", STATE.roundSwaps), nil)
    end
end

--- 绘制底部栏（模仿 reCAPTCHA 底部）
local function drawFooter(ctx, cardX, cardW, y, footerH)
    nvgBeginPath(ctx)
    nvgRoundedRectVarying(ctx, cardX, y, cardW, footerH, 0, 0, 8, 8)
    nvgFillColor(ctx, nvgRGBA(table.unpack(COLORS.footerBg)))
    nvgFill(ctx)

    -- 分割线
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, cardX, y)
    nvgLineTo(ctx, cardX + cardW, y)
    nvgStrokeColor(ctx, nvgRGBA(220, 220, 220, 255))
    nvgStrokeWidth(ctx, 1)
    nvgStroke(ctx)

    -- 图标区
    local iconY = y + footerH / 2
    local iconStartX = cardX + 20

    -- 刷新图标 (简化圆弧)
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, 20)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(100, 100, 100, 255))
    nvgText(ctx, iconStartX, iconY, "↻", nil)

    -- 耳机图标
    nvgText(ctx, iconStartX + 32, iconY, "🎧", nil)

    -- 机器人图标
    nvgText(ctx, iconStartX + 64, iconY, "🤖", nil)

    -- 右侧: 轮次 / 最佳成绩
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, 10)
    nvgTextAlign(ctx, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(ctx, nvgRGBA(table.unpack(COLORS.textLight)))
    local infoText = string.format("Round %d", STATE.round)
    if STATE.bestTime < math.huge then
        infoText = infoText .. string.format("  |  Best: %.2fs", STATE.bestTime)
    end
    nvgText(ctx, cardX + cardW - 16, iconY, infoText, nil)
end

--- 绘制结果页面
local function drawResultOverlay(ctx, cx, cy, cardW)
    local isRobot = STATE.phase == "verified"

    -- 半透明遮罩
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, SCREEN.logW, SCREEN.logH)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, 100))
    nvgFill(ctx)

    -- 结果卡片
    local rw = cardW - 40
    local rh = 260
    local rx = cx - rw / 2
    local ry = cy - rh / 2

    drawShadow(ctx, rx, ry, rw, rh, 12, 16)
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, rx, ry, rw, rh, 12)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 250))
    nvgFill(ctx)

    if isRobot then
        -- 机器人验证成功
        -- 绿色大圆勾
        local checkCx = cx
        local checkCy = ry + 55
        nvgBeginPath(ctx)
        nvgCircle(ctx, checkCx, checkCy, 30)
        nvgFillColor(ctx, nvgRGBA(76, 175, 80, 255))
        nvgFill(ctx)

        nvgFontFace(ctx, "bold")
        nvgFontSize(ctx, 32)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
        nvgText(ctx, checkCx, checkCy, "✓", nil)

        nvgFontFace(ctx, "bold")
        nvgFontSize(ctx, 20)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(ctx, nvgRGBA(76, 175, 80, 255))
        nvgText(ctx, cx, ry + 95, "验证通过！", nil)

        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, 14)
        nvgFillColor(ctx, nvgRGBA(table.unpack(COLORS.textDark)))
        nvgText(ctx, cx, ry + 125, "确认您是机器人", nil)

        nvgFontSize(ctx, 12)
        nvgFillColor(ctx, nvgRGBA(table.unpack(COLORS.textLight)))
        nvgText(ctx, cx, ry + 150,
            string.format("用时 %.2f 秒 · %d 次交换", STATE.elapsed, STATE.roundSwaps), nil)

        -- 倒计时
        nvgFontSize(ctx, 13)
        nvgFillColor(ctx, nvgRGBA(66, 133, 244, 255))
        nvgText(ctx, cx, ry + 180,
            string.format("%.1f 秒后跳转...", math.max(0, STATE.verifiedCountdown)), nil)

        -- 跳转链接提示
        nvgFontSize(ctx, 9)
        nvgFillColor(ctx, nvgRGBA(table.unpack(COLORS.textLight)))
        nvgText(ctx, cx, ry + 210, "即将前往 bilibili.com", nil)
    else
        -- 人类结果
        -- 红色 X
        local xCx = cx
        local xCy = ry + 55
        nvgBeginPath(ctx)
        nvgCircle(ctx, xCx, xCy, 30)
        nvgFillColor(ctx, nvgRGBA(244, 67, 54, 255))
        nvgFill(ctx)

        nvgFontFace(ctx, "bold")
        nvgFontSize(ctx, 32)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(255, 255, 255, 255))
        nvgText(ctx, xCx, xCy, "✗", nil)

        nvgFontFace(ctx, "bold")
        nvgFontSize(ctx, 20)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(ctx, nvgRGBA(244, 67, 54, 255))
        nvgText(ctx, cx, ry + 95, "验证失败", nil)

        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, 14)
        nvgFillColor(ctx, nvgRGBA(table.unpack(COLORS.textDark)))
        nvgText(ctx, cx, ry + 125, "您似乎不是机器人", nil)

        nvgFontSize(ctx, 12)
        nvgFillColor(ctx, nvgRGBA(table.unpack(COLORS.textLight)))
        nvgText(ctx, cx, ry + 150,
            string.format("用时 %.2f 秒 · %d 次交换", STATE.elapsed, STATE.roundSwaps), nil)

        nvgText(ctx, cx, ry + 170,
            string.format("需要 ≤ %.1f 秒 才能通过", CONFIG.ROBOT_TIME), nil)

        -- 继续按钮提示
        nvgFontSize(ctx, 13)
        nvgFillColor(ctx, nvgRGBA(66, 133, 244, 255))
        nvgText(ctx, cx, ry + 210, "[ 点击任意处继续下一轮 ]", nil)

        -- 历次成绩
        if #STATE.history > 1 then
            nvgFontSize(ctx, 10)
            nvgFillColor(ctx, nvgRGBA(table.unpack(COLORS.textLight)))
            local histStr = "历史: "
            local startIdx = math.max(1, #STATE.history - 4)
            for i = startIdx, #STATE.history do
                histStr = histStr .. string.format("R%d=%.2fs ", STATE.history[i].round, STATE.history[i].time)
            end
            nvgText(ctx, cx, ry + rh - 16, histStr, nil)
        end
    end
end

--- 主渲染
function HandleNanoVGRender(eventType, eventData)
    if not nvgCtx_ then return end

    local ctx = nvgCtx_

    -- 更新屏幕信息
    SCREEN.w = graphics:GetWidth()
    SCREEN.h = graphics:GetHeight()
    SCREEN.dpr = graphics:GetDPR()
    SCREEN.logW = SCREEN.w / SCREEN.dpr
    SCREEN.logH = SCREEN.h / SCREEN.dpr

    nvgBeginFrame(ctx, SCREEN.w, SCREEN.h, SCREEN.dpr)

    local logW = SCREEN.logW
    local logH = SCREEN.logH

    -- 背景
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, logW, logH)
    nvgFillColor(ctx, nvgRGBA(table.unpack(COLORS.bg)))
    nvgFill(ctx)

    -- 卡片尺寸
    local cardW = math.min(360, logW - 32)
    local cardH = 480
    local cardX = (logW - cardW) / 2
    local cardY = math.max(20, (logH - cardH) / 2 - 20)
    local cx = logW / 2

    -- 卡片阴影
    drawShadow(ctx, cardX, cardY, cardW, cardH, 8, 12)

    -- 卡片背景
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, cardX, cardY, cardW, cardH, 8)
    nvgFillColor(ctx, nvgRGBA(table.unpack(COLORS.cardBg)))
    nvgFill(ctx)
    nvgStrokeColor(ctx, nvgRGBA(table.unpack(COLORS.cardBorder)))
    nvgStrokeWidth(ctx, 1)
    nvgStroke(ctx)

    -- 头部
    local contentY = drawHeader(ctx, cx, cardX, cardW, cardY)

    -- 计时器
    drawTimer(ctx, cx, contentY + 30)

    -- 柱状图区域
    local barsBottomY = cardY + cardH - 70
    CONFIG.AREA_BOTTOM_Y = barsBottomY
    drawBars(ctx, barsBottomY)

    -- 底部栏
    drawFooter(ctx, cardX, cardW, cardY + cardH - 50, 50)

    -- 结果 / 验证成功遮罩
    if STATE.phase == "result" or STATE.phase == "verified" then
        drawResultOverlay(ctx, cx, logH / 2, cardW)
    end

    -- idle 提示覆盖
    if STATE.phase == "idle" then
        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, 12)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(ctx, nvgRGBA(66, 133, 244, 200))
        nvgText(ctx, cx, barsBottomY + 8, "↕ 拖动任意柱子开始计时", nil)
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
    local bottomY = CONFIG.AREA_BOTTOM_Y
    for i = 1, #STATE.bars do
        local bx = getBarX(i)
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

    -- 在结果页点击: 进入下一轮
    if STATE.phase == "result" then
        nextRound()
        return
    end

    -- 验证成功页不处理点击
    if STATE.phase == "verified" then return end

    -- 点击柱子开始拖拽
    local idx = hitTestBar(lx, ly)
    if idx >= 1 then
        -- 第一次拖拽开始计时
        if STATE.phase == "idle" then
            beginSorting()
        end

        DRAG.active = true
        DRAG.barIndex = idx
        DRAG.startX = getBarX(idx) + CONFIG.BAR_WIDTH / 2
        DRAG.currentX = lx
        DRAG.currentY = ly
        DRAG.offsetX = lx - (getBarX(idx) + CONFIG.BAR_WIDTH / 2)
    end
end

function HandleMouseMove(eventType, eventData)
    if not DRAG.active then return end

    local sx = eventData["X"]:GetInt()
    local sy = eventData["Y"]:GetInt()
    local lx, ly = screenToLogical(sx, sy)

    DRAG.currentX = lx
    DRAG.currentY = ly

    -- 实时交换：当拖到另一个柱子的位置时交换
    local targetIdx = getBarIndexAtX(lx)
    if targetIdx >= 1 and targetIdx ~= DRAG.barIndex then
        -- 交换数据
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

        -- 检查是否排序完成
        if STATE.phase == "sorting" then
            checkComplete()
        end
    end
end

-- 触摸事件处理（移动端适配）
function HandleTouchBegin(eventType, eventData)
    local sx = eventData["X"]:GetInt()
    local sy = eventData["Y"]:GetInt()
    local lx, ly = screenToLogical(sx, sy)

    if STATE.phase == "result" then
        nextRound()
        return
    end
    if STATE.phase == "verified" then return end

    local idx = hitTestBar(lx, ly)
    if idx >= 1 then
        if STATE.phase == "idle" then
            beginSorting()
        end
        DRAG.active = true
        DRAG.barIndex = idx
        DRAG.startX = getBarX(idx) + CONFIG.BAR_WIDTH / 2
        DRAG.currentX = lx
        DRAG.currentY = ly
        DRAG.offsetX = lx - (getBarX(idx) + CONFIG.BAR_WIDTH / 2)
    end
end

function HandleTouchMove(eventType, eventData)
    if not DRAG.active then return end
    local sx = eventData["X"]:GetInt()
    local sy = eventData["Y"]:GetInt()
    local lx, ly = screenToLogical(sx, sy)
    DRAG.currentX = lx
    DRAG.currentY = ly

    local targetIdx = getBarIndexAtX(lx)
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
        if STATE.phase == "sorting" then
            checkComplete()
        end
    end
end

-- ============================================================================
-- 更新循环
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 验证成功倒计时跳转
    if STATE.phase == "verified" then
        STATE.verifiedCountdown = STATE.verifiedCountdown - dt
        if STATE.verifiedCountdown <= 0 then
            -- 执行跳转
            print("=== Redirecting to: " .. CONFIG.REDIRECT_URL .. " ===")
            OpenURL(CONFIG.REDIRECT_URL)
            STATE.phase = "idle"  -- 防止重复跳转
        end
    end
end

-- ============================================================================
-- 入口
-- ============================================================================

function Start()
    graphics.windowTitle = "roBOTCHA - 机器人验证"

    math.randomseed(os.time())

    -- 初始化 UI 系统
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 初始化 NanoVG (独立上下文用于自定义渲染)
    initNanoVG()

    -- 创建 UI
    CreateUI()

    -- 初始化游戏
    startNewRound()

    -- 订阅事件
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("MouseButtonDown", "HandleMouseButtonDown")
    SubscribeToEvent("MouseMove", "HandleMouseMove")
    SubscribeToEvent("MouseButtonUp", "HandleMouseButtonUp")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
    SubscribeToEvent("TouchMove", "HandleTouchMove")
    SubscribeToEvent("TouchEnd", "HandleTouchEnd")

    print("=== roBOTCHA Started ===")
    print("Sort the bars from short to tall.")
    print("Complete in under 1 second to prove you're a robot!")
end

function Stop()
    if nvgCtx_ then
        nvgDelete(nvgCtx_)
        nvgCtx_ = nil
    end
    UI.Shutdown()
end
