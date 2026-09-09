-- ============================================================================
-- Storage.lua - 本地存档系统
-- 对应 H5: localStorage 完成记录 + 偏好存储
-- ============================================================================

local Storage = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

local SAVE_FILE = "save_data.json"
local data_ = {
    completions = {},   -- {gameName -> {timestamp, difficulty}}
    preferences = {},   -- 用户偏好
    unlockedGames = {}, -- {gameId, ...}
}

-- ============================================================================
-- 初始化
-- ============================================================================

function Storage.Init()
    Storage.Load()
    print("[Storage] Init, completions=" .. #data_.completions)
end

-- ============================================================================
-- 存取
-- ============================================================================

--- 从文件加载存档
function Storage.Load()
    if not fileSystem:FileExists(SAVE_FILE) then
        print("[Storage] No save file found, using defaults")
        return
    end

    local file = File(SAVE_FILE, FILE_READ)
    if not file then
        print("[Storage] Cannot open save file")
        return
    end

    local content = file:ReadString()
    file:Close()
    file:Dispose()

    if not content or #content == 0 then return end

    local ok, loaded = pcall(cjson.decode, content)
    if ok and type(loaded) == "table" then
        data_.completions = loaded.completions or {}
        data_.preferences = loaded.preferences or {}
        data_.unlockedGames = loaded.unlockedGames or {}
        print("[Storage] Loaded OK")
    else
        print("[Storage] Parse error: " .. tostring(loaded))
    end
end

--- 保存存档到文件
function Storage.Save()
    local content = cjson.encode(data_)
    local file = File(SAVE_FILE, FILE_WRITE)
    if not file then
        print("[Storage] Cannot write save file")
        return
    end
    file:WriteString(content)
    file:Close()
    file:Dispose()
    print("[Storage] Saved")
end

-- ============================================================================
-- 完成记录
-- ============================================================================

--- 记录一次通关
---@param gameName string
---@param difficulty string
function Storage.RecordCompletion(gameName, difficulty)
    data_.completions[#data_.completions + 1] = {
        gameName = gameName,
        difficulty = difficulty,
        timestamp = os.time(),
    }
    Storage.Save()
    print("[Storage] Recorded completion: " .. gameName .. " (" .. difficulty .. ")")
end

--- 获取通关记录列表
---@return table[]
function Storage.GetCompletions()
    return data_.completions
end

--- 是否已通关过某游戏
---@param gameName string
---@return boolean
function Storage.HasCompleted(gameName)
    for _, record in ipairs(data_.completions) do
        if record.gameName == gameName then
            return true
        end
    end
    return false
end

-- ============================================================================
-- 偏好设置
-- ============================================================================

--- 设置偏好
---@param key string
---@param value any
function Storage.SetPreference(key, value)
    data_.preferences[key] = value
    Storage.Save()
end

--- 获取偏好
---@param key string
---@param default any
---@return any
function Storage.GetPreference(key, default)
    local val = data_.preferences[key]
    if val == nil then return default end
    return val
end

-- ============================================================================
-- 游戏解锁（看广告解锁付费故事）
-- ============================================================================

---@param gameId string
---@param isFree boolean|nil
---@return boolean
function Storage.IsGameUnlocked(gameId, isFree)
    if isFree then
        return true
    end
    for _, id in ipairs(data_.unlockedGames or {}) do
        if id == gameId then
            return true
        end
    end
    return false
end

---@param gameId string
function Storage.UnlockGame(gameId)
    if Storage.IsGameUnlocked(gameId, false) then
        return
    end
    data_.unlockedGames[#data_.unlockedGames + 1] = gameId
    Storage.Save()
    print("[Storage] Unlocked game: " .. tostring(gameId))
end

return Storage
