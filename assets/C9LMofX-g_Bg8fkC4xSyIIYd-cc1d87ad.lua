-- ============================================================================
-- UI_Message.lua - 消息队列
-- 对应 H5: useGameEngine.ts 的 msgQueue / isTextPlaying / queueLog / advanceLog
-- ============================================================================

local GameState = require("GameState")
local Audio = require("Audio")

---@type fun()
RefreshGameUI = RefreshGameUI

local UI_Message = {}

---@type string[]
local msgQueue_ = {}
---@type string|nil
local currentMsg_ = nil
local skipDelay_ = false
local autoTimer_ = 0.0
local autoWaiting_ = false

local AUTO_DELAY = 2.0

function UI_Message.Init()
    msgQueue_ = {}
    currentMsg_ = nil
    skipDelay_ = false
    autoTimer_ = 0.0
    autoWaiting_ = false
end

--- 对应 H5 isTextPlaying：队列里还有未写入日志的句子
function UI_Message.IsPlaying()
    return #msgQueue_ > 0
end

function UI_Message.GetCurrentMessage()
    return currentMsg_
end

function UI_Message.HasQueued()
    return #msgQueue_ > 0
end

--- 对应 H5 advanceLog：把队首写入日志
function UI_Message.Advance()
    if #msgQueue_ == 0 then
        return
    end

    currentMsg_ = table.remove(msgQueue_, 1)
    -- 点击/空格推进后重置 2 秒计时（对应 H5 useEffect 因 msgQueue 变化重建 timer）
    autoWaiting_ = #msgQueue_ > 0
    autoTimer_ = AUTO_DELAY

    local log = GameState.GetLog()
    local last = log[#log]
    if currentMsg_ and currentMsg_ ~= last then
        GameState.AddLog(currentMsg_)
    end
    Audio.PlaySound("click")
    if RefreshGameUI then
        RefreshGameUI()
    end
end

--- 对应 H5 queueLog：入队；本批第一条立即显示，其余 2 秒自动推进
---@param messages string[]|string
function UI_Message.QueueMessages(messages)
    if type(messages) == "string" then
        messages = { messages }
    end
    if not messages or #messages == 0 then
        return
    end

    local wasEmpty = #msgQueue_ == 0
    for _, msg in ipairs(messages) do
        if msg and #msg > 0 then
            msgQueue_[#msgQueue_ + 1] = msg
        end
    end
    if #msgQueue_ == 0 then
        return
    end

    if wasEmpty then
        -- 本批第一条立即写入日志（对应 H5 shouldSkipDelay + 立刻 advance）
        UI_Message.Advance()
        -- 剩余句子走 2 秒自动推进，不立刻再推进
        skipDelay_ = false
        autoWaiting_ = #msgQueue_ > 0
        autoTimer_ = AUTO_DELAY
    elseif RefreshGameUI then
        RefreshGameUI()
    end
end

--- 对应 H5 useEffect：队列非空时每 2 秒自动 advanceLog
---@param dt number
function UI_Message.Update(dt)
    if #msgQueue_ == 0 then
        autoWaiting_ = false
        autoTimer_ = 0.0
        return
    end

    if not autoWaiting_ then
        autoWaiting_ = true
        if skipDelay_ then
            autoTimer_ = 0.0
        else
            autoTimer_ = AUTO_DELAY
        end
        skipDelay_ = false
    end

    autoTimer_ = autoTimer_ - dt
    if autoTimer_ <= 0 then
        autoWaiting_ = false
        UI_Message.Advance()
        if #msgQueue_ > 0 then
            autoWaiting_ = true
            autoTimer_ = AUTO_DELAY
        end
    end
end

function UI_Message.CreateWidget()
    -- 消息只显示在底部日志；全屏点击层在 UI_Game 中创建
    return nil
end

return UI_Message
