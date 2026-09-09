-- ============================================================================
-- Hint.lua - 提示系统
-- 对应 H5: services/hintService.ts + App.tsx handleHint
-- ============================================================================

local GameState = require("GameState")
local GameEngine = require("GameEngine")
local UI_Message = require("UI_Message")
local Audio = require("Audio")
local Ads = require("Ads")

---@type fun()
RefreshGameUI = RefreshGameUI
---@type fun(): table|nil
GetGameData = GetGameData

local Hint = {}

local remaining_ = 2
local lastHintText_ = nil
local adPromptOpen_ = false

function Hint.Init()
    remaining_ = 2
    lastHintText_ = nil
    adPromptOpen_ = false
end

function Hint.Reset()
    remaining_ = 2
    lastHintText_ = nil
    adPromptOpen_ = false
end

function Hint.GetRemaining()
    return remaining_
end

local function isVisible(inter)
    if inter.requiredFlag and not GameState.GetFlag(inter.requiredFlag) then
        return false
    end
    return true
end

local function isRevealed(inter, sceneId)
    return GameState.GetFlag("revealed_" .. sceneId .. "_" .. inter.id) == true
end

local function hasInteracted(inter, sceneId)
    return GameState.GetFlag("interacted_" .. sceneId .. "_" .. inter.id) == true
end

--- 提示用：排除“已经看过、没有后续操作”的线索源
---@param inter table
---@param sceneId string
---@return boolean
local function hasRemainingHintWork(inter, sceneId)
    if GameEngine.IsInteractableCompleted(inter, sceneId) then
        return false
    end
    if inter.isPuzzle or inter.puzzleId then
        return true
    end
    if inter.itemRewardId and not GameState.GetFlag("found_" .. inter.itemRewardId) then
        return true
    end
    if inter.requiredItemId then
        local unlocked = GameState.GetFlag("unlocked_" .. sceneId .. "_" .. inter.id)
            or (inter.flagReward and GameState.GetFlag(inter.flagReward))
        if not unlocked then
            return true
        end
    end
    -- 纯线索/对话：看过一次就不再提示调查
    if hasInteracted(inter, sceneId) then
        return false
    end
    return true
end

--- 生成一条提示（对应 H5 generateHint）
---@param gameData table
---@return table|nil {text=string, costsUse=boolean, type=string}
function Hint.Generate(gameData)
    if not gameData then return nil end
    local currentSceneId = GameState.ResolveActiveSceneId()
    local currentScene = gameData.scenes[currentSceneId]
    if not currentScene then return nil end

    local allInScene = {}
    for _, inter in ipairs(currentScene.interactables or {}) do
        if isVisible(inter) and hasRemainingHintWork(inter, currentSceneId) then
            allInScene[#allInScene + 1] = inter
        end
    end

    local interactables = {}
    local hasUnrevealed = false
    for _, inter in ipairs(allInScene) do
        if isRevealed(inter, currentSceneId) then
            interactables[#interactables + 1] = inter
        else
            hasUnrevealed = true
        end
    end

    if #interactables == 0 and hasUnrevealed then
        return { type = "explore", text = "这个房间还有东西没发现，试试使用探索", costsUse = false }
    end

    local inventory = GameState.GetInventory()
    local function hasItem(itemId)
        for _, id in ipairs(inventory) do
            if id == itemId then return true end
        end
        return false
    end

    -- 1. 当前场景：物品可用
    for _, inter in ipairs(interactables) do
        if inter.requiredItemId and hasItem(inter.requiredItemId) then
            local item = gameData.items[inter.requiredItemId]
            local itemName = (item and item.name) or inter.requiredItemId
            local interName = inter.name or inter.id
            return { type = "use_item", text = "「" .. itemName .. "」可以在「" .. interName .. "」上使用", costsUse = true }
        end
    end

    -- 2. 当前场景：谜题+持有线索
    for _, inter in ipairs(interactables) do
        if inter.isPuzzle or inter.puzzleId then
            local puzzleId = inter.puzzleId or inter.id
            local puzzleName = inter.name or puzzleId
            for itemId, item in pairs(gameData.items or {}) do
                if item.clueForPuzzleId == puzzleId and hasItem(itemId) then
                    return { type = "solve_puzzle", text = "在「" .. (item.name or itemId) .. "」中有「" .. puzzleName .. "」的线索", costsUse = true }
                end
            end
        end
    end

    -- 3. 其他场景：物品可用
    for sceneId, scene in pairs(gameData.scenes or {}) do
        if sceneId ~= currentSceneId then
            for _, inter in ipairs(scene.interactables or {}) do
                if isVisible(inter) and hasRemainingHintWork(inter, sceneId) and isRevealed(inter, sceneId) then
                    if inter.requiredItemId and hasItem(inter.requiredItemId) then
                        local item = gameData.items[inter.requiredItemId]
                        local itemName = (item and item.name) or inter.requiredItemId
                        local interName = inter.name or inter.id
                        local sceneName = scene.title or sceneId
                        return { type = "go_scene", text = "去「" .. sceneName .. "」，「" .. itemName .. "」可以在「" .. interName .. "」上使用", costsUse = true }
                    end
                end
            end
        end
    end

    -- 3.5 其他场景：谜题+线索
    for sceneId, scene in pairs(gameData.scenes or {}) do
        if sceneId ~= currentSceneId then
            for _, inter in ipairs(scene.interactables or {}) do
                if isVisible(inter) and hasRemainingHintWork(inter, sceneId)
                    and isRevealed(inter, sceneId) and (inter.isPuzzle or inter.puzzleId) then
                    local puzzleId = inter.puzzleId or inter.id
                    local puzzleName = inter.name or puzzleId
                    for itemId, item in pairs(gameData.items or {}) do
                        if item.clueForPuzzleId == puzzleId and hasItem(itemId) then
                            local sceneName = scene.title or sceneId
                            return { type = "go_scene", text = "去「" .. sceneName .. "」，在「" .. (item.name or itemId) .. "」中有「" .. puzzleName .. "」的线索", costsUse = true }
                        end
                    end
                end
            end
        end
    end

    -- 4. 当前场景：给物品的交互
    for _, inter in ipairs(interactables) do
        if inter.itemRewardId then
            if not inter.requiredItemId or hasItem(inter.requiredItemId) then
                return { type = "explore", text = "试试调查「" .. (inter.name or inter.id) .. "」", costsUse = false }
            end
        end
    end

    -- 5. 当前场景：普通交互
    for _, inter in ipairs(interactables) do
        if not inter.itemRewardId and not inter.isPuzzle and not inter.puzzleId then
            if not inter.requiredItemId or hasItem(inter.requiredItemId) then
                return { type = "explore", text = "试试调查「" .. (inter.name or inter.id) .. "」", costsUse = false }
            end
        end
    end

    -- 6. 其他场景还有未完成事项
    for sceneId, scene in pairs(gameData.scenes or {}) do
        if sceneId ~= currentSceneId then
            for _, inter in ipairs(scene.interactables or {}) do
                if isVisible(inter) and hasRemainingHintWork(inter, sceneId) and isRevealed(inter, sceneId) then
                    return { type = "go_scene", text = "去「" .. (scene.title or sceneId) .. "」看看，那里还有未完成的事", costsUse = false }
                end
            end
        end
    end

    if hasUnrevealed then
        return { type = "explore", text = "试试使用探索，发现更多线索", costsUse = false }
    end
    return nil
end

function Hint.AddUses(count)
    remaining_ = remaining_ + (count or 0)
    if RefreshGameUI then RefreshGameUI() end
end

function Hint.IsAdPromptOpen()
    return adPromptOpen_
end

local function deliverHint(hint)
    if not hint then
        UI_Message.QueueMessages({ "当前没有更多提示，试试探索周围" })
        return
    end
    if hint.costsUse and remaining_ > 0 and hint.text ~= lastHintText_ then
        remaining_ = remaining_ - 1
        lastHintText_ = hint.text
    end
    UI_Message.QueueMessages({ "提示：" .. hint.text })
    Audio.PlaySound("click")
    if RefreshGameUI then RefreshGameUI() end
end

function Hint.ConfirmWatchAd()
    if Ads.IsInFlight() then
        return
    end
    adPromptOpen_ = false
    if RefreshGameUI then RefreshGameUI() end
    Ads.ShowReward(function()
        remaining_ = remaining_ + 2
        Audio.PlaySound("success")
        UI_Message.QueueMessages({ "获得2次提示机会！" })
        if RefreshGameUI then RefreshGameUI() end
    end, function()
        UI_Message.QueueMessages({ "广告未完成，请稍后再试" })
    end)
end

function Hint.CancelWatchAd()
    adPromptOpen_ = false
    if RefreshGameUI then RefreshGameUI() end
end

--- 点击提示按钮
function Hint.Request()
    if adPromptOpen_ then
        return
    end
    local gameData = GetGameData and GetGameData() or nil
    local hint = Hint.Generate(gameData)
    if not hint then
        UI_Message.QueueMessages({ "当前没有更多提示，试试探索周围" })
        return
    end
    if hint.costsUse and remaining_ <= 0 then
        adPromptOpen_ = true
        if RefreshGameUI then RefreshGameUI() end
        return
    end
    deliverHint(hint)
end

return Hint
