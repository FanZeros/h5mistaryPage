-- ============================================================================
-- GameState.lua - 游戏状态管理
-- 对应 H5: useGameEngine 中的 gameState/setGameState
-- ============================================================================

local GameState = {}

-- 当前游戏状态
local state_ = {
    currentSceneId = "start",
    inventory = {},       -- string[] 物品ID列表
    flags = {},           -- Record<string, boolean|number>
    log = {},             -- string[] 历史日志
    gameOver = false,
    gameWon = false,
    difficulty = "EASY",  -- "EASY" | "STANDARD"
}

-- 游戏定义数据引用
local gameData_ = nil

-- ============================================================================
-- 初始化与重置
-- ============================================================================

--- 初始化状态模块（持有游戏数据引用）
---@param gameData table
function GameState.Init(gameData)
    gameData_ = gameData
    if gameData and gameData.initialState then
        GameState.Reset("EASY")
    end
end

--- 重置游戏状态到初始
---@param difficulty string "EASY" | "STANDARD"
function GameState.Reset(difficulty)
    if not gameData_ or not gameData_.initialState then
        print("[GameState] WARNING: No gameData to reset from")
        return
    end
    local init = gameData_.initialState
    state_ = {
        currentSceneId = init.currentSceneId or "start",
        inventory = {},
        flags = {},
        log = {},
        gameOver = false,
        gameWon = false,
        difficulty = difficulty or "EASY",
    }
    -- 深拷贝 inventory
    if init.inventory then
        for _, id in ipairs(init.inventory) do
            state_.inventory[#state_.inventory + 1] = id
        end
    end
    -- 深拷贝 flags
    if init.flags then
        for k, v in pairs(init.flags) do
            state_.flags[k] = v
        end
    end
    print("[GameState] Reset. Scene=" .. state_.currentSceneId .. " Difficulty=" .. state_.difficulty)
end

-- ============================================================================
-- 场景
-- ============================================================================

--- 获取当前场景ID
---@return string
function GameState.GetCurrentSceneId()
    return state_.currentSceneId
end

--- 设置当前场景
---@param sceneId string
function GameState.SetCurrentScene(sceneId)
    state_.currentSceneId = sceneId
end

--- 解析活跃场景ID（考虑 conditionalVariant）
---@return string
function GameState.ResolveActiveSceneId()
    local baseId = state_.currentSceneId
    if not gameData_ or not gameData_.scenes[baseId] then
        return baseId
    end
    local scene = gameData_.scenes[baseId]
    if scene.conditionalVariant then
        local cond = scene.conditionalVariant
        local met = true
        if cond.requiredItemId and not GameState.HasItem(cond.requiredItemId) then
            met = false
        end
        if cond.requiredFlag and not state_.flags[cond.requiredFlag] then
            met = false
        end
        if met then
            return cond.targetSceneId
        end
    end
    return baseId
end

-- ============================================================================
-- 物品栏
-- ============================================================================

--- 获取物品栏列表
---@return string[]
function GameState.GetInventory()
    return state_.inventory
end

--- 是否拥有某物品
---@param itemId string
---@return boolean
function GameState.HasItem(itemId)
    for _, id in ipairs(state_.inventory) do
        if id == itemId then return true end
    end
    return false
end

--- 添加物品到背包
---@param itemId string
function GameState.AddItem(itemId)
    if not GameState.HasItem(itemId) then
        state_.inventory[#state_.inventory + 1] = itemId
        state_.flags["found_" .. itemId] = true
        print("[GameState] +Item: " .. itemId)
    end
end

--- 移除物品
---@param itemId string
function GameState.RemoveItem(itemId)
    for i, id in ipairs(state_.inventory) do
        if id == itemId then
            table.remove(state_.inventory, i)
            print("[GameState] -Item: " .. itemId)
            return
        end
    end
end

-- ============================================================================
-- 标志位 (Flags)
-- ============================================================================

--- 获取标志位值
---@param key string
---@return boolean|number|nil
function GameState.GetFlag(key)
    return state_.flags[key]
end

--- 设置标志位
---@param key string
---@param value boolean|number
function GameState.SetFlag(key, value)
    state_.flags[key] = value
end

--- 批量设置标志位
---@param flagTable table<string, boolean|number>
function GameState.SetFlags(flagTable)
    for k, v in pairs(flagTable) do
        state_.flags[k] = v
    end
end

--- 获取所有标志位
---@return table<string, boolean|number>
function GameState.GetAllFlags()
    return state_.flags
end

-- ============================================================================
-- 日志
-- ============================================================================

--- 添加日志条目
---@param msg string
function GameState.AddLog(msg)
    if not msg or msg == "" then return end
    local last = state_.log[#state_.log]
    if last == msg then return end
    state_.log[#state_.log + 1] = msg
    -- 控制日志长度，避免无限增长
    if #state_.log > 40 then
        table.remove(state_.log, 1)
    end
end

--- 获取日志
---@return string[]
function GameState.GetLog()
    return state_.log
end

-- ============================================================================
-- 游戏结束状态
-- ============================================================================

--- 是否已胜利
---@return boolean
function GameState.IsGameWon()
    return state_.gameWon
end

--- 设置游戏胜利
function GameState.SetGameWon()
    state_.gameWon = true
    print("[GameState] GAME WON!")
    local Storage = require("Storage")
    local Data = require("Data")
    local gameId = Data.currentGameId
    if gameId and gameId ~= "" and not Storage.HasCompleted(gameId) then
        Storage.RecordCompletion(gameId, state_.difficulty)
    end
end

--- 是否已结束
---@return boolean
function GameState.IsGameOver()
    return state_.gameOver
end

--- 获取难度
---@return string
function GameState.GetDifficulty()
    return state_.difficulty
end

-- ============================================================================
-- 物品详情查询 (便捷方法)
-- ============================================================================

--- 获取背包中的物品详细信息列表
---@return table[]
function GameState.GetInventoryItems()
    local result = {}
    if not gameData_ then return result end
    for _, id in ipairs(state_.inventory) do
        local item = gameData_.items[id]
        if item then
            result[#result + 1] = item
        end
    end
    return result
end

return GameState
