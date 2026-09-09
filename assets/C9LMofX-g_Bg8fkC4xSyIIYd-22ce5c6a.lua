-- ============================================================================
-- UI_Message.lua - 消息弹出层
-- 多条消息需点击逐步显示，弹出层放在场景底部，不挡住操作按钮
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("GameState")
local Audio = require("Audio")

---@type fun()
RefreshGameUI = RefreshGameUI

local UI_Message = {}

local msgQueue_ = {}
local currentMsg_ = nil
local isActive_ = false

function UI_Message.Init()
    msgQueue_ = {}
    currentMsg_ = nil
    isActive_ = false
end

function UI_Message.IsPlaying()
    return isActive_
end

function UI_Message.GetCurrentMessage()
    return currentMsg_
end

function UI_Message.HasQueued()
    return #msgQueue_ > 0
end

local function showNext()
    if #msgQueue_ == 0 then
        currentMsg_ = nil
        isActive_ = false
        if RefreshGameUI then
            RefreshGameUI()
        end
        return
    end

    currentMsg_ = table.remove(msgQueue_, 1)
    isActive_ = true

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

--- 向队列中添加消息。多条时先显示第一条，其余点击后再显示
---@param messages string[]|string
function UI_Message.QueueMessages(messages)
    if type(messages) == "string" then
        messages = { messages }
    end
    if not messages or #messages == 0 then
        return
    end

    for _, msg in ipairs(messages) do
        if msg and #msg > 0 then
            msgQueue_[#msgQueue_ + 1] = msg
        end
    end

    if not isActive_ then
        showNext()
    elseif RefreshGameUI then
        RefreshGameUI()
    end
end

function UI_Message.Advance()
    if #msgQueue_ == 0 then
        currentMsg_ = nil
        isActive_ = false
        if RefreshGameUI then
            RefreshGameUI()
        end
        return
    end
    showNext()
end

function UI_Message.Update(dt)
end

function UI_Message.CreateWidget()
    if not isActive_ or not currentMsg_ or #currentMsg_ == 0 then
        return nil
    end

    return UI.Panel {
        id = "msgPanel",
        position = "absolute",
        left = 16,
        right = 108,
        bottom = 228,
        paddingTop = 14,
        paddingRight = 16,
        paddingBottom = 18,
        paddingLeft = 16,
        backgroundColor = { 0, 0, 0, 210 },
        borderRadius = 12,
        borderWidth = 1,
        borderColor = { 100, 116, 139, 160 },
        pointerEvents = "auto",
        onClick = function(self)
            UI_Message.Advance()
        end,
        children = {
            UI.Label {
                text = currentMsg_,
                fontSize = 15,
                fontColor = { 240, 240, 240, 255 },
                width = "100%",
                lineHeight = 1.5,
                whiteSpace = "normal",
                wordBreak = "break-word",
            },
            UI.Label {
                text = (#msgQueue_ > 0) and "点击继续" or "点击关闭",
                fontSize = 11,
                fontColor = { 251, 191, 36, 220 },
               ginTop = 8,
                textAlign = "right",
                width = "100%",
            },
        }
    }
end

return UI_Message
