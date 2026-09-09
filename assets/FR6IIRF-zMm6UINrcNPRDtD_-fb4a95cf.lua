-- ============================================================================
-- 谜题解谜游戏引擎 (Mystery Puzzle Game Engine)
-- 移植自 H5 版本，使用 UrhoX UI 系统
-- ============================================================================

local UI = require("urhox-libs/UI")

-- 模块引入
local Data = require("Data")
local GameState = require("GameState")
local GameEngine = require("GameEngine")
local Audio = require("Audio")
local Storage = require("Storage")
local UI_GameSelect = require("UI_GameSelect")
local UI_Title = require("UI_Title")
local UI_Game = require("UI_Game")
local UI_Message = require("UI_Message")
local UI_Puzzle = require("UI_Puzzle")
local Hint = require("Hint")

-- ============================================================================
-- 全局变量
-- ============================================================================

---@type table|nil
local gameData_ = nil       -- 当前加载的游戏定义数据
---@type table|nil
local gameList_ = nil       -- 游戏列表数据
local gamePhase_ = "select" -- "select" | "loading" | "title" | "game" | "victory"
local uiRoot_ = nil         -- UI 根控件引用
local restDownloadReady_ = true
local restDownloadTotal_ = 0
local restDownloadDone_ = 0
---@type integer|nil
local restDownloadGroupId_ = nil
local pendingLogScroll_ = 0

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    graphics.windowTitle = "迷境探索"

    -- 1. 初始化 UI 系统：使用中文像素字体
    local PixelTheme = UI.Theme.ExtendTheme(UI.Theme.defaultTheme, {
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/FusionPixel-12px-Prop-zh_hans.ttf",
                bold = "Fonts/FusionPixel-12px-Prop-zh_hans-Bold.ttf",
            } },
            { family = "mono", weights = {
                normal = "Fonts/FusionPixel-12px-Mono-zh_hans.ttf",
            } },
        },
        typography = {
            fontFamily = "sans",
        },
    })
    UI.Init({
        theme = PixelTheme,
        scale = UI.Scale.DEFAULT,
    })

    -- 2. 加载游戏列表
    gameList_ = Data.LoadGameList()
    if not gameList_ or #gameList_ == 0 then
        print("[Main] WARNING: No games found in games.json, using fallback")
        gameList_ = {}
    end

    -- 3. 初始化基础子系统
    Storage.Init()
    UI_Message.Init()
    UI_Puzzle.Init()
    Hint.Init()

    -- 4. 默认进入「千禧倒计时」，没有则回退到选关列表
    local defaultGame = nil
    for _, game in ipairs(gameList_) do
        if game.id == "millennium-countdown" then
            defaultGame = game
            break
        end
    end
    if not defaultGame and #gameList_ > 0 then
        defaultGame = gameList_[1]
    end
    if defaultGame then
        OnGameSelected(defaultGame)
    else
        ShowGameSelectScreen()
    end

    -- 5. 订阅事件
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")

    print("=== Mystery Game Engine Started ===")
end

function Stop()
    Audio.Shutdown()
    UI.Shutdown()
end

-- ============================================================================
-- 画面切换
-- ============================================================================

function ShowGameSelectScreen()
    gamePhase_ = "select"
    if restDownloadGroupId_ then
        cache:CancelDownloadGroup(restDownloadGroupId_)
        restDownloadGroupId_ = nil
    end
    restDownloadReady_ = true
    restDownloadTotal_ = 0
    restDownloadDone_ = 0
    Audio.StopBGM()

    ---@type Widget
    local root = UI_GameSelect.Create(gameList_, function(gameEntry)
        OnGameSelected(gameEntry)
    end)
    UI.SetRoot(root)
    uiRoot_ = root
    print("[Main] Phase -> select")
end

--- 选择了一个游戏后：先加载标题封面+BGM，再进入标题页并后台加载其余资源
---@param gameEntry table 游戏列表中的条目
function OnGameSelected(gameEntry)
    print("[Main] Loading game: " .. gameEntry.name .. " from: " .. gameEntry.path)
    restDownloadReady_ = true
    restDownloadTotal_ = 0
    restDownloadDone_ = 0
    restDownloadGroupId_ = nil

    local loadedData = Data.LoadGameData(gameEntry.path)
    if loadedData then
        gameData_ = loadedData
        print("[Main] Game loaded OK: " .. (gameData_.meta.name or "Unknown"))
    else
        print("[Main] ERROR: Failed to load game: " .. gameEntry.path)
        gameData_ = Data.GetDefaultGame()
        gameData_.meta.name = gameEntry.name
        gameData_.meta.description = gameEntry.description or ""
    end

    -- 初始化游戏相关子系统（切换游戏时完全重置）
    GameState.Init(gameData_)
    GameEngine.Init(gameData_)
    GameEngine.Reset()
    Audio.Init(gameData_)
    UI_Message.Init()
    UI_Puzzle.Init()
    Hint.Reset()

    local titlePaths, restPaths = Data.CollectMediaPathGroups(gameData_)
    restDownloadTotal_ = #restPaths
    restDownloadDone_ = 0
    restDownloadReady_ = (#restPaths == 0)
    print("[Main] DWP title=" .. #titlePaths .. " rest=" .. #restPaths)

    local function enterTitleAndLoadRest()
        ShowTitleScreen()
        StartRestResourceDownload(restPaths)
    end

    if #titlePaths > 0 then
        ShowLoadingScreen(gameEntry.name, #titlePaths)
        cache:DownloadResources(titlePaths,
            function(success, failedCount)
                print("[Main] Title assets ready. success=" .. tostring(success)
                    .. ", failed=" .. tostring(failedCount))
                enterTitleAndLoadRest()
            end,
            function(completed, total, downloadedBytes, totalBytes)
                UpdateLoadingProgress(completed, total)
            end
        )
    else
        enterTitleAndLoadRest()
    end
end

--- 显示加载画面
---@param gameName string
---@param totalCount number
function ShowLoadingScreen(gameName, totalCount)
    gamePhase_ = "loading"
    local root = UI.Panel {
        id = "loadingRoot",
        width = "100%", height = "100%",
        backgroundColor = { 5, 7, 12, 255 },
        justifyContent = "center",
        alignItems = "center",
        gap = 16,
        children = {
            UI.Label {
                text = "加载中",
                fontSize = 22,
                fontColor = { 245, 158, 11, 255 },
            },
            UI.Label {
                id = "loadingTitle",
                text = "正在加载「" .. gameName .. "」",
                fontSize = 16,
                fontColor = { 245, 158, 11, 255 },
                textAlign = "center",
            },
            -- 进度条容器
            UI.Panel {
                width = "60%",
                maxWidth = 260,
                height = 8,
                backgroundColor = { 30, 41, 59, 255 },
                borderRadius = 4,
                overflow = "hidden",
                children = {
                    UI.Panel {
                        id = "loadingBar",
                        width = "5%",
                        height = "100%",
                        backgroundColor = { 245, 158, 11, 255 },
                        borderRadius = 4,
                    },
                },
            },
            UI.Label {
                id = "loadingProgress",
                text = "0 / " .. totalCount,
                fontSize = 11,
                fontColor = { 100, 116, 139, 200 },
            },
        }
    }
    UI.SetRoot(root)
    uiRoot_ = root
end

--- 更新加载进度
---@param completed number
---@param total number
function UpdateLoadingProgress(completed, total)
    if not uiRoot_ then return end
    local pct = (total > 0) and math.floor((completed / total) * 100) or 0
    local bar = uiRoot_:FindById("loadingBar")
    if bar then
        bar:SetStyle({ width = pct .. "%" })
    end
    local label = uiRoot_:FindById("loadingProgress")
    if label then
        label:SetText(completed .. " / " .. total)
    end
end

function ShowTitleScreen()
    gamePhase_ = "title"
    ---@type Widget
    local root = UI_Title.Create(gameData_, function(difficulty)
        OnGameStart(difficulty)
    end, {
        restTotal = restDownloadReady_ and 0 or restDownloadTotal_,
    })
    UI.SetRoot(root)
    uiRoot_ = root
    Audio.PlayBGM()
    if not restDownloadReady_ then
        UpdateTitleLoadingProgress(restDownloadDone_, restDownloadTotal_)
    end
    print("[Main] Phase -> title")
end

--- 标题页后台下载场景/物品资源
---@param restPaths string[]
function StartRestResourceDownload(restPaths)
    if not restPaths or #restPaths == 0 then
        restDownloadReady_ = true
        restDownloadTotal_ = 0
        restDownloadDone_ = 0
        return
    end
    restDownloadReady_ = false
    restDownloadTotal_ = #restPaths
    restDownloadDone_ = 0
    restDownloadGroupId_ = cache:DownloadResources(restPaths,
        function(success, failedCount)
            restDownloadReady_ = true
            restDownloadDone_ = restDownloadTotal_
            restDownloadGroupId_ = nil
            print("[Main] Rest assets ready. success=" .. tostring(success)
                .. ", failed=" .. tostring(failedCount))
            if gamePhase_ == "title" then
                UpdateTitleLoadingProgress(restDownloadTotal_, restDownloadTotal_)
                EnableTitleStartButtons()
            end
        end,
        function(completed, total, downloadedBytes, totalBytes)
            restDownloadDone_ = completed
            restDownloadTotal_ = total
            if gamePhase_ == "title" then
                UpdateTitleLoadingProgress(completed, total)
            end
        end
    )
end

--- 更新标题页后台加载进度
---@param completed number
---@param total number
function UpdateTitleLoadingProgress(completed, total)
    if not uiRoot_ or gamePhase_ ~= "title" then return end
    local pct = (total > 0) and math.floor((completed / total) * 100) or 100
    local bar = uiRoot_:FindById("titleLoadingBar")
    if bar then
        bar:SetStyle({ width = math.max(4, pct) .. "%" })
    end
    local label = uiRoot_:FindById("titleLoadingText")
    if label then
        if completed >= total then
            label:SetText("场景资源已就绪")
        else
            label:SetText("正在加载场景资源 " .. completed .. " / " .. total)
        end
    end
end

function EnableTitleStartButtons()
    if not uiRoot_ or gamePhase_ ~= "title" then return end
    local easyBtn = uiRoot_:FindById("titleEasyBtn")
    if easyBtn then
        if easyBtn.SetDisabled then easyBtn:SetDisabled(false) end
        if easyBtn.SetText then easyBtn:SetText("简单") end
    end
    local standardBtn = uiRoot_:FindById("titleStandardBtn")
    if standardBtn then
        if standardBtn.SetDisabled then standardBtn:SetDisabled(false) end
        if standardBtn.SetText then standardBtn:SetText("标准") end
    end
    local wrap = uiRoot_:FindById("titleLoadingWrap")
    if wrap and wrap.SetVisible then
        wrap:SetVisible(false)
    end
end

function OnGameStart(difficulty)
    if not restDownloadReady_ then
        print("[Main] Start blocked: rest assets still loading")
        return
    end
    gamePhase_ = "game"
    GameState.Reset(difficulty)
    GameEngine.Reset()
    Hint.Reset()
    UI_Message.Init()

    -- 显示开场描述
    local introLogs = gameData_.initialState.log
    if introLogs and #introLogs > 0 then
        UI_Message.QueueMessages(introLogs)
    end

    RebuildGameUI()
    Audio.PlaySound("transition")
    print("[Main] Phase -> game, difficulty=" .. difficulty)
end

function OnGameVictory()
    gamePhase_ = "victory"
    RebuildGameUI()
    print("[Main] Phase -> victory")
end

function OnGameRestart()
    GameState.Reset(GameState.GetDifficulty())
    GameEngine.Reset()
    Hint.Reset()
    UI_Message.Init()
    gamePhase_ = "game"
    local introLogs = gameData_.initialState.log
    if introLogs and #introLogs > 0 then
        UI_Message.QueueMessages(introLogs)
    end
    RebuildGameUI()
    Audio.PlaySound("transition")
    print("[Main] Phase -> game (restart)")
end

function RebuildGameUI()
    ---@type Widget
    local root = UI_Game.Create(gameData_, gamePhase_)
    UI.SetRoot(root)
    uiRoot_ = root
    -- 等布局完成后再滚到日志底部，避免内容高度尚未更新
    pendingLogScroll_ = 2
end

--- 外部可调用的 UI 刷新
function RefreshGameUI()
    if gamePhase_ == "game" or gamePhase_ == "victory" then
        RebuildGameUI()
    end
end

-- ============================================================================
-- 更新循环
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 消息队列自动推进
    UI_Message.Update(dt)

    -- 日志栏滚到最新一条（对应 H5 scrollIntoView）
    if pendingLogScroll_ > 0 and uiRoot_ then
        pendingLogScroll_ = pendingLogScroll_ - 1
        if pendingLogScroll_ <= 0 then
            local logPanel = uiRoot_:FindById("logPanel")
            if logPanel and logPanel.SetScroll then
                if logPanel.UpdateContentSize then
                    logPanel:UpdateContentSize()
                end
                local layout = logPanel.GetLayout and logPanel:GetLayout() or nil
                local contentH = logPanel.contentHeight_ or 0
                local viewH = layout and layout.h or 0
                local maxY = math.max(0, contentH - viewH)
                logPanel:SetScroll(0, maxY)
            end
        end
    end

    -- 搜查放大镜动画
    if gamePhase_ == "game" then
        UI_Game.UpdateAnimation(dt)
    end

    -- 探索系统计时器
    if gamePhase_ == "game" then
        GameEngine.UpdateExploration(dt)
    end

    -- 检查胜利条件
    if gamePhase_ == "game" and GameState.IsGameWon() then
        OnGameVictory()
    end
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    -- ESC: 关闭谜题面板/退出探索
    if key == KEY_ESCAPE then
        if UI_Puzzle.IsOpen() then
            UI_Puzzle.Close()
        elseif UI_Game.IsInspecting and UI_Game.IsInspecting() then
            UI_Game.CloseInspect()
        elseif GameEngine.IsExploring() then
            GameEngine.StopExploration()
        end
        return
    end

    -- Space/Enter: 推进消息
    if (key == KEY_SPACE or key == KEY_RETURN) and UI_Message.IsPlaying() then
        UI_Message.Advance()
        return
    end
end

-- ============================================================================
-- 全局访问接口 (供子模块回调)
-- ============================================================================

--- 获取当前游戏数据
function GetGameData()
    return gameData_
end

--- 获取游戏列表
function GetGameList()
    return gameList_
end

--- 获取当前游戏阶段
function GetGamePhase()
    return gamePhase_
end

--- 获取 UI 根控件
function GetUIRoot()
    return uiRoot_
end
