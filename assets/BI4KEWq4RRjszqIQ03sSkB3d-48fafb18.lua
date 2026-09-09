-- ============================================================================
-- Data.lua - 游戏数据加载与清洗
-- 对应 H5: types.ts + gameLogicUtils.ts (sanitizeGameData)
-- ============================================================================

local Data = {}

-- ============================================================================
-- 资源文件读取辅助
-- assets/ 下的文件是打包资源，必须通过 ResourceCache 读取，
-- 不能用 fileSystem:FileExists / File()（后者读的是可写沙箱目录）
-- ============================================================================

--- 读取资源文件为字符串
---@param name string 资源相对路径 (如 "games.json" / "games/abyss/game.json")
---@return string|nil
local function readResourceText(name)
    if not cache:Exists(name) then
        return nil
    end
    local file = cache:GetFile(name)
    if not file then
        return nil
    end
    local content = file:ReadString()
    file:Dispose()
    if not content or #content == 0 then
        return nil
    end
    return content
end

-- ============================================================================
-- 默认游戏数据 (当 game.json 加载失败时使用)
-- ============================================================================

local DEFAULT_GAME = {
    meta = {
        name = "默认游戏",
        author = "System",
        version = "1.0.0",
        description = "游戏数据未正确加载。",
    },
    initialState = {
        currentSceneId = "start",
        inventory = {},
        flags = {},
        log = { "加载失败，请检查 game.json 文件。" },
        gameOver = false,
        gameWon = false,
        difficulty = "EASY",
    },
    items = {},
    scenes = {
        start = {
            id = "start",
            title = "起点",
            imageUrl = "",
            description = "游戏未正确加载。",
            interactables = {},
            exits = {},
        }
    },
    puzzles = {},
    marketing = {},
}

-- ============================================================================
-- 数据清洗 (对应 H5 sanitizeGameData)
-- ============================================================================

--- 确保值是 table（数组或对象），否则返回默认值
---@param val any
---@param default table
---@return table
local function ensureTable(val, default)
    if type(val) == "table" then
        return val
    end
    return default
end

--- 确保值是字符串
---@param val any
---@param default string
---@return string
local function ensureString(val, default)
    if type(val) == "string" then
        return val
    end
    return default or ""
end

--- 去掉 emoji / 符号，避免当前字体显示成口口
---@param text string|nil
---@param fallback string
---@return string
local function stripEmoji(text, fallback)
    if type(text) ~= "string" or text == "" then
        return fallback
    end
    local cleaned = {}
    for _, code in utf8.codes(text) do
        local keep = (code >= 0x4E00 and code <= 0x9FFF)
            or (code >= 0x3400 and code <= 0x4DBF)
            or (code >= 0x30 and code <= 0x39)
            or (code >= 0x41 and code <= 0x5A)
            or (code >= 0x61 and code <= 0x7A)
            or code == 0x5F
            or code == 0x2D
        if keep then
            cleaned[#cleaned + 1] = utf8.char(code)
        end
    end
    local result = table.concat(cleaned)
    if result == "" then
        return fallback
    end
    return result
end

--- 清洗单个 Interactable 数据
---@param inter table
---@return table
local function sanitizeInteractable(inter)
    if type(inter) ~= "table" then return nil end
    -- 字段归一化: rewardFlag -> flagReward (旧版兼容)
    if inter.rewardFlag and not inter.flagReward then
        inter.flagReward = inter.rewardFlag
        inter.rewardFlag = nil
    end
    -- 确保 dialogue 是数组
    inter.dialogue = ensureTable(inter.dialogue, {})
    -- 确保 id 存在
    inter.id = ensureString(inter.id, "unnamed_" .. tostring(math.random(10000)))
    inter.name = ensureString(inter.name, "???")
    inter.description = ensureString(inter.description, "")
    return inter
end

--- 清洗单个 Scene 数据
---@param scene table
---@return table
local function sanitizeScene(scene)
    if type(scene) ~= "table" then return nil end
    scene.id = ensureString(scene.id, "unknown_scene")
    scene.title = ensureString(scene.title, "未命名场景")
    scene.imageUrl = ensureString(scene.imageUrl, "")
    scene.description = ensureString(scene.description, "")
    scene.interactables = ensureTable(scene.interactables, {})
    scene.exits = ensureTable(scene.exits, {})

    -- 清洗每个交互物
    local cleanInteractables = {}
    for i, inter in ipairs(scene.interactables) do
        local cleaned = sanitizeInteractable(inter)
        if cleaned then
            cleanInteractables[#cleanInteractables + 1] = cleaned
        end
    end
    scene.interactables = cleanInteractables

    -- 确保每个出口有必要字段
    for i, exit in ipairs(scene.exits) do
        exit.direction = ensureString(exit.direction, "north")
        exit.targetSceneId = ensureString(exit.targetSceneId, "")
        exit.label = ensureString(exit.label, exit.direction)
    end

    return scene
end

--- 清洗单个 Puzzle 数据
---@param puzzle table
---@return table
local function sanitizePuzzle(puzzle)
    if type(puzzle) ~= "table" then return nil end
    puzzle.id = ensureString(puzzle.id, "unknown_puzzle")
    puzzle.description = ensureString(puzzle.description, "")
    puzzle.answer = ensureString(puzzle.answer, "")
    puzzle.type = ensureString(puzzle.type, "text")
    puzzle.choices = ensureTable(puzzle.choices, {})
    -- 字段归一化
    if puzzle.rewardFlag and not puzzle.rewardFlag then
        -- 已经是 rewardFlag，保持
    end
    puzzle.rewardFlag = ensureString(puzzle.rewardFlag, "puzzle_" .. puzzle.id .. "_solved")
    puzzle.rewardMessage = ensureString(puzzle.rewardMessage, "解答正确。")
    puzzle.points = ensureTable(puzzle.points, {})
    puzzle.connections = ensureTable(puzzle.connections, {})
    puzzle.gridSize = puzzle.gridSize
    puzzle.linkedAssetId = puzzle.linkedAssetId
    return puzzle
end

--- 清洗单个 Item 数据
---@param item table
---@return table
local function sanitizeItem(item)
    if type(item) ~= "table" then return nil end
    item.id = ensureString(item.id, "unknown_item")
    item.name = ensureString(item.name, "未知物品")
    item.description = ensureString(item.description, "")
    item.type = ensureString(item.type, "TOOL")
    item.icon = stripEmoji(ensureString(item.icon, "物品"), "物品")
    return item
end

--- 完整清洗游戏数据
---@param raw table
---@return table
local function sanitizeGameData(raw)
    if type(raw) ~= "table" then
        return DEFAULT_GAME
    end

    local data = {}

    -- Meta
    data.meta = ensureTable(raw.meta, {})
    data.meta.name = ensureString(data.meta.name, "未命名游戏")
    data.meta.author = ensureString(data.meta.author, "")
    data.meta.version = ensureString(data.meta.version, "1.0.0")
    data.meta.description = ensureString(data.meta.description, "")

    -- Marketing
    data.marketing = ensureTable(raw.marketing, {})

    -- Initial State
    data.initialState = ensureTable(raw.initialState, {})
    data.initialState.currentSceneId = ensureString(data.initialState.currentSceneId, "start")
    data.initialState.inventory = ensureTable(data.initialState.inventory, {})
    data.initialState.flags = ensureTable(data.initialState.flags, {})
    data.initialState.log = ensureTable(data.initialState.log, {})
    data.initialState.gameOver = data.initialState.gameOver or false
    data.initialState.gameWon = data.initialState.gameWon or false
    data.initialState.difficulty = ensureString(data.initialState.difficulty, "EASY")

    -- Items (对象表 id -> Item)
    data.items = {}
    local rawItems = ensureTable(raw.items, {})
    for id, item in pairs(rawItems) do
        local cleaned = sanitizeItem(item)
        if cleaned then
            cleaned.id = id
            data.items[id] = cleaned
        end
    end

    -- Puzzles (对象表 id -> Puzzle)
    data.puzzles = {}
    local rawPuzzles = ensureTable(raw.puzzles, {})
    for id, puzzle in pairs(rawPuzzles) do
        local cleaned = sanitizePuzzle(puzzle)
        if cleaned then
            cleaned.id = id
            data.puzzles[id] = cleaned
        end
    end

    -- Scenes (对象表 id -> Scene)
    data.scenes = {}
    local rawScenes = ensureTable(raw.scenes, {})
    for id, scene in pairs(rawScenes) do
        local cleaned = sanitizeScene(scene)
        if cleaned then
            cleaned.id = id
            data.scenes[id] = cleaned
        end
    end

    return data
end

-- ============================================================================
-- 公共 API
-- ============================================================================

--- 当前游戏的基路径 (如 "games/millennium-countdown/")
---@type string
Data.currentGameBaseDir = ""
Data.currentGameId = ""

--- 加载游戏列表
---@return table|nil  游戏列表数组
function Data.LoadGameList()
    local path = "games.json"
    print("[Data] Loading game list from: " .. path)

    local content = readResourceText(path)
    if not content then
        print("[Data] ERROR: games.json not found or empty")
        return nil
    end

    local ok, decoded = pcall(cjson.decode, content)
    if not ok then
        print("[Data] ERROR: games.json parse failed: " .. tostring(decoded))
        return nil
    end

    ---@cast decoded table

    -- 读取打包配置，过滤游戏列表
    local packContent = readResourceText("pack-config.json")
    if packContent then
        local pok, packCfg = pcall(cjson.decode, packContent)
        if pok and packCfg and packCfg.include and #packCfg.include > 0 then
            -- 构建 include 集合
            local includeSet = {}
            for _, id in ipairs(packCfg.include) do
                includeSet[id] = true
            end
            -- 过滤：仅保留 include 中的游戏，保持 include 顺序
            local filtered = {}
            for _, id in ipairs(packCfg.include) do
                for _, g in ipairs(decoded) do
                    if g.id == id then
                        filtered[#filtered + 1] = g
                        break
                    end
                end
            end
            print("[Data] Pack config applied: " .. #filtered .. "/" .. #decoded .. " games included")
            return filtered
        end
    end

    -- 无 pack-config 或配置无效时，返回全部
    print("[Data] Game list loaded: " .. #decoded .. " games (no pack filter)")
    return decoded
end

--- 加载游戏数据文件
---@param path string JSON 文件相对路径 (如 "games/abyss/game.json")
---@return table|nil
function Data.LoadGameData(path)
    print("[Data] Loading game data from: " .. path)

    -- 从路径提取游戏基目录 (如 "games/abyss/game.json" -> "games/abyss/")
    local baseDir = path:match("^(.*/)")
    if baseDir then
        Data.currentGameBaseDir = baseDir
        Data.currentGameId = baseDir:match("games/([^/]+)/") or ""
    else
        Data.currentGameBaseDir = ""
        Data.currentGameId = ""
    end
    print("[Data] Game base dir: " .. Data.currentGameBaseDir)

    local content = readResourceText(path)
    if not content then
        print("[Data] ERROR: File not found or empty: " .. path)
        return nil
    end

    local ok, rawData = pcall(cjson.decode, content)
    if not ok then
        print("[Data] ERROR: JSON parse failed: " .. tostring(rawData))
        return nil
    end

    local cleanData = sanitizeGameData(rawData)
    print("[Data] Loaded OK: " .. cleanData.meta.name .. " (scenes=" .. Data.CountTable(cleanData.scenes) .. ", items=" .. Data.CountTable(cleanData.items) .. ", puzzles=" .. Data.CountTable(cleanData.puzzles) .. ")")
    return cleanData
end

--- 获取默认游戏数据
---@return table
function Data.GetDefaultGame()
    return DEFAULT_GAME
end

--- 计算 table 中的元素数量(用于对象表)
---@param t table
---@return integer
function Data.CountTable(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

--- 解析资源路径 (适配多游戏子目录结构)
--- 规则:
---   "./assets/millennium-countdown/scene_xxx.jpg" -> "games/millennium-countdown/scene_xxx.jpg"
---   "./assets/scene_xxx.jpg" -> "games/[currentGameId]/scene_xxx.jpg" (旧格式，纯文件名)
---   "./assets/bgm.mp3" -> "games/[currentGameId]/bgm.mp3"
--- 额外: 若文件不存在，自动尝试 .png<->.jpg 扩展名 fallback
---@param rawPath string|nil
---@return string
function Data.ResolveAssetPath(rawPath)
    if not rawPath or rawPath == "" then
        return ""
    end
    -- 外部 URL 保持原样，由运行时下载/播放
    if rawPath:find("^https?://") then
        return rawPath
    end
    -- 移除 "./assets/" 或 "assets/" 前缀
    local path = rawPath
    path = path:gsub("^%./assets/", "")
    path = path:gsub("^assets/", "")

    -- 如果路径已经含有子目录 (如 "millennium-countdown/scene_xxx.jpg")
    -- 则直接加上 "games/" 前缀
    local resolved
    if path:find("/") then
        resolved = "games/" .. path
    else
        -- 纯文件名 (旧格式如 "scene_xxx.jpg") -> 使用当前游戏基目录
        resolved = Data.currentGameBaseDir .. path
    end

    -- 扩展名多重检测: 依次尝试原路径、.jpg、.png，返回第一个存在的
    if cache:Exists(resolved) then
        return resolved
    end

    local base, ext = resolved:match("^(.+)(%.%w+)$")
    if base then
        -- 尝试 .jpg
        local jpgPath = base .. ".jpg"
        if jpgPath ~= resolved and cache:Exists(jpgPath) then
            return jpgPath
        end
        -- 尝试 .png
        local pngPath = base .. ".png"
        if pngPath ~= resolved and cache:Exists(pngPath) then
            return pngPath
        end
    end

    -- 都找不到，返回原始路径（让引擎报错便于排查）
    return resolved
end

-- ============================================================================
-- DWP 辅助：收集游戏的所有媒体资源路径（用于预下载）
-- ============================================================================

--- 收集游戏数据中所有需要下载的媒体资源路径
--- 包括：场景图片、物品图片、BGM、标题封面
---@param gameData table 已清洗的游戏数据
---@return string[] 资源虚拟路径列表
function Data.CollectMediaPaths(gameData)
    local titlePaths, restPaths = Data.CollectMediaPathGroups(gameData)
    local paths = {}
    for i = 1, #titlePaths do
        paths[#paths + 1] = titlePaths[i]
    end
    for i = 1, #restPaths do
        paths[#paths + 1] = restPaths[i]
    end
    return paths
end

--- 分两组收集媒体：标题页必需资源 / 进入探索后才需要的资源
---@param gameData table 已清洗的游戏数据
---@return string[] titlePaths
---@return string[] restPaths
function Data.CollectMediaPathGroups(gameData)
    local titlePaths = {}
    local restPaths = {}
    local seen = {}

    local function add(target, rawPath)
        if not rawPath or rawPath == "" then return end
        if type(rawPath) == "string" and rawPath:find("^https?://") then
            return
        end
        local resolved = Data.ResolveAssetPath(rawPath)
        if resolved == "" or seen[resolved] then return end
        if resolved:find("^https?://") then return end
        seen[resolved] = true
        target[#target + 1] = resolved
    end

    -- 标题页：封面图 + BGM，优先加载
    if gameData.marketing then
        add(titlePaths, gameData.marketing.bannerUrl)
    end
    if gameData.meta then
        add(titlePaths, gameData.meta.banner)
        add(titlePaths, gameData.meta.bgmUrl)
        add(titlePaths, gameData.meta.musicUrl)
    end
    if Data.currentGameBaseDir and Data.currentGameBaseDir ~= "" then
        local hasBanner = false
        local hasBgm = false
        for _, path in ipairs(titlePaths) do
            if path:find("%.jpg$") or path:find("%.png$") or path:find("%.jpeg$") or path:find("%.webp$") then
                hasBanner = true
            elseif path:find("bgm%.") or path:find("%.mp3$") or path:find("%.ogg$") or path:find("%.wav$") then
                hasBgm = true
            end
        end
        if not hasBanner then
            local bannerFallbacks = {
                Data.currentGameBaseDir .. "game_banner_1080.jpg",
                Data.currentGameBaseDir .. "marketing_banner.jpg",
                Data.currentGameBaseDir .. "banner.jpg",
            }
            for _, candidate in ipairs(bannerFallbacks) do
                if cache:Exists(candidate) and not seen[candidate] then
                    seen[candidate] = true
                    titlePaths[#titlePaths + 1] = candidate
                    break
                end
            end
        end
        if not hasBgm then
            local bgmFallbacks = {
                Data.currentGameBaseDir .. "bgm.mp3",
                Data.currentGameBaseDir .. "bgm.ogg",
                Data.currentGameBaseDir .. "bgm.wav",
            }
            for _, candidate in ipairs(bgmFallbacks) do
                if cache:Exists(candidate) and not seen[candidate] then
                    seen[candidate] = true
                    titlePaths[#titlePaths + 1] = candidate
                    break
                end
            end
        end
    end

    -- 其余：场景图、物品图，标题页后台继续加载
    if gameData.scenes then
        for _, scene in pairs(gameData.scenes) do
            add(restPaths, scene.imageUrl)
        end
    end
    if gameData.items then
        for _, item in pairs(gameData.items) do
            add(restPaths, item.image)
            add(restPaths, item.imageUrl)
        end
    end

    return titlePaths, restPaths
end

return Data
