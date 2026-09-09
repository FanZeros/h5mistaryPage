-- ============================================================================
-- UI_Game.lua - 主游戏界面
-- 对应 H5: App.tsx 游戏画面 (横向布局: 左侧场景区 + 右侧背包栏)
--   左侧: 场景图 + 边缘出口按钮 + 顶栏(场景名/探索) + 底部交互物面板/日志
--   右侧: 竖排背包栏 (物品 PNG 缩略图)
-- ============================================================================

local UI = require("urhox-libs/UI")
local Data = require("Data")
local GameState = require("GameState")
local GameEngine = require("GameEngine")
local UI_Message = require("UI_Message")
local UI_Puzzle = require("UI_Puzzle")
local Hint = require("Hint")
local Widget = require("urhox-libs/UI/Core/Widget")

local searchIconAngle_ = 0
local dragScroll_ = {
    active = false,
    lastY = 0,
    moved = false,
}

--- 给 ScrollView 加上手指/鼠标拖动滚动
---@param widget table
---@param onTap fun()|nil
local function bindDragScroll(widget, onTap)
    if not widget then
        return
    end
    widget.props.pointerEvents = "auto"
    widget.OnPanStart = function(self, event)
        if not self.props.scrollX and not self.props.scrollY then
            return false
        end
        if self.CancelSnap_ then
            self:CancelSnap_()
        end
        self.state.isDragging = true
        self.dragStartScrollX_ = self.state.scrollX or 0
        self.dragStartScrollY_ = self.state.scrollY or 0
        self.state.velocityX = 0
        self.state.velocityY = 0
        dragScroll_.moved = false
        return true
    end
    widget.OnPanMove = function(self, event)
        if not self.state.isDragging then
            return
        end
        local dx = self.props.scrollX and -(event.totalDeltaX or 0) or 0
        local dy = self.props.scrollY and -(event.totalDeltaY or 0) or 0
        if math.abs(event.totalDeltaY or 0) > 4 or math.abs(event.totalDeltaX or 0) > 4 then
            dragScroll_.moved = true
        end
        if self.SetScroll then
            self:SetScroll(self.dragStartScrollX_ + dx, self.dragStartScrollY_ + dy)
        end
        self.state.velocityX = -(event.deltaX or 0)
        self.state.velocityY = -(event.deltaY or 0)
    end
    widget.OnPanEnd = function(self, event)
        self.state.isDragging = false
        if not dragScroll_.moved and onTap then
            onTap()
        end
        dragScroll_.moved = false
    end
    return widget
end


---@class GameIcon : Widget
---@field props table
local GameIcon = UI.Widget:Extend("GameIcon")

---@param props table
function GameIcon:Init(props)
    props = props or {}
    props.width = props.width or 18
    props.height = props.height or 18
    props.flexShrink = 0
    Widget.Init(self, props)
end

---@param nvg NVGContextWrapper
function GameIcon:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local props = self.props
    local color = props.color or { 226, 232, 240, 255 }
    local shadow = props.shadowColor or { 8, 12, 22, 210 }
    local kind = props.kind or "hint"

    local patterns = {
        search = {
            ".####...",
            "##..##..",
            "#....#..",
            "#....#..",
            "##..##..",
            ".####...",
            ".....##.",
            "......##",
        },
        hint = {
            "..####..",
            ".######.",
            ".##..##.",
            ".######.",
            "..####..",
            "...##...",
            "..####..",
            "...##...",
        },
        expand = {
            "........",
            "........",
            "##....##",
            ".##..##.",
            "..####..",
            "...##...",
            "........",
            "........",
        },
        collapse = {
            "........",
            "........",
            "...##...",
            "..####..",
            ".##..##.",
            "##....##",
            "........",
            "........",
        },
        north = {
            "...##...",
            "..####..",
            ".######.",
            "##.##.##",
            "...##...",
            "...##...",
            "...##...",
            "...##...",
        },
        south = {
            "...##...",
            "...##...",
            "...##...",
            "...##...",
            "##.##.##",
            ".######.",
            "..####..",
            "...##...",
        },
        west = {
            "...#....",
            "..##....",
            ".#######",
            "########",
            "########",
            ".#######",
            "..##....",
            "...#....",
        },
        east = {
            "....#...",
            "....##..",
            "#######.",
            "########",
            "########",
            "#######.",
            "....##..",
            "....#...",
        },
        lock = {
            "..####..",
            ".##..##.",
            ".##..##.",
            "########",
            "##.##.##",
            "##.##.##",
            "########",
            "########",
        },
    }

    local pattern = patterns[kind] or patterns.hint
    local cell = math.max(2, math.floor(math.min(l.w, l.h) / 9))
    local pixelW = 8 * cell
    local pixelH = 8 * cell
    local orbitX, orbitY = 0, 0
    if kind == "search" and props.animating then
        local orbitRadius = cell * 0.9
        orbitX = math.cos(searchIconAngle_) * orbitRadius
        orbitY = math.sin(searchIconAngle_) * orbitRadius
    end
    local startX = math.floor(l.x + (l.w - pixelW) * 0.5 + orbitX)
    local startY = math.floor(l.y + (l.h - pixelH) * 0.5 + orbitY)

    local function drawPattern(offsetX, offsetY, fillColor)
        nvgFillColor(nvg, nvgRGBA(fillColor[1], fillColor[2], fillColor[3], fillColor[4] or 255))
        nvgBeginPath(nvg)
        for row = 1, 8 do
            local line = tostring(pattern[row] or "........")
            for col = 1, 8 do
                if line:sub(col, col) == "#" then
                    nvgRect(nvg,
                        startX + (col - 1) * cell + offsetX,
                        startY + (row - 1) * cell + offsetY,
                        cell,
                        cell)
                end
            end
        end
        nvgFill(nvg)
    end

    -- 无模糊硬阴影 + 像素主体
    drawPattern(math.max(1, math.floor(cell * 0.55)), math.max(1, math.floor(cell * 0.55)), shadow)
    drawPattern(0, 0, color)
end

---@type fun()
RefreshGameUI = RefreshGameUI
---@type fun()
OnGameRestart = OnGameRestart
---@type fun()
ShowGameSelectScreen = ShowGameSelectScreen

local UI_Game = {}

-- 右侧背包栏宽度
local INVENTORY_WIDTH = 92

-- 物品查看状态（点击已选中物品 → 打开大图详情）
local inspectingItemId_ = nil
-- 底部日志展开（对应 H5 isExpanded）
local logExpanded_ = true

--- 更新搜查图标动画
---@param dt number
function UI_Game.UpdateAnimation(dt)
    searchIconAngle_ = (searchIconAngle_ + dt * 4.5) % (math.pi * 2)
end

--- 关闭物品查看弹窗
function UI_Game.CloseInspect()
    inspectingItemId_ = nil
    if RefreshGameUI then RefreshGameUI() end
end

--- 方向图标映射
local DIR_ICONS = {
    north = "北",
    south = "南",
    east = "东",
    west = "西",
    up = "上",
    down = "下",
}

-- 前置声明
local CreateSceneViewport
local CreateExitEdges
local CreateBottomPanel
local CreateInventorySidebar
local CreateItemInspectModal
local CreateVictoryOverlay

-- ============================================================================
-- 主入口
-- ============================================================================

--- 创建游戏主界面 UI 树
---@param gameData table 游戏数据
---@param gamePhase string "game" | "victory"
---@return table UI root widget
function UI_Game.Create(gameData, gamePhase)
    -- 进入新游戏/非游戏阶段时清除查看状态
    if gamePhase ~= "game" and gamePhase ~= "victory" then
        inspectingItemId_ = nil
    end

    local activeSceneId = GameState.ResolveActiveSceneId()
    local scene = gameData.scenes[activeSceneId]

    -- 左侧主区（场景视口 + 底部交互面板）
    local leftColumn = UI.Panel {
        id = "leftColumn",
        flexGrow = 1,
        flexShrink = 1,
        minWidth = 0,
        height = "100%",
        flexDirection = "column",
        children = {
            CreateSceneViewport(gameData, scene, activeSceneId),
            CreateBottomPanel(gameData, scene),
        }
    }

    -- 右侧背包栏
    local sidebar = CreateInventorySidebar(gameData)

    -- 主体横向分栏
    local mainSplit = UI.Panel {
        id = "mainSplit",
        width = "100%",
        height = "100%",
        flexDirection = "row",
        children = { leftColumn, sidebar },
    }

    local children = { mainSplit }

    -- 物品查看弹窗（对应 H5 inspectingItem 覆盖层）
    if inspectingItemId_ and gameData.items[inspectingItemId_] then
        children[#children + 1] = CreateItemInspectModal(gameData.items[inspectingItemId_])
    end

    if Hint.IsAdPromptOpen and Hint.IsAdPromptOpen() then
        children[#children + 1] = UI.Panel {
            id = "hintAdPrompt",
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            backgroundColor = { 0, 0, 0, 180 },
            justifyContent = "center",
            alignItems = "center",
            pointerEvents = "auto",
            children = {
                UI.Panel {
                    width = "80%",
                    maxWidth = 360,
                    padding = 24,
                    gap = 16,
                    backgroundColor = { 15, 23, 42, 250 },
                    borderRadius = 16,
                    borderWidth = 1,
                    borderColor = { 71, 85, 105, 200 },
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = "看广告获取提示",
                            fontSize = 20,
                            fontColor = { 245, 193, 67, 255 },
                        },
                        UI.Label {
                            text = "观看完整广告后可获得 2 次提示",
                            fontSize = 14,
                            fontColor = { 226, 232, 240, 255 },
                            textAlign = "center",
                            width = "100%",
                            whiteSpace = "normal",
                        },
                        UI.Button {
                            text = "看广告",
                            variant = "primary",
                            width = "80%",
                            onClick = function(self)
                                Hint.ConfirmWatchAd()
                            end,
                        },
                        UI.Button {
                            text = "取消",
                            variant = "ghost",
                            onClick = function(self)
                                Hint.CancelWatchAd()
                            end,
                        },
                    }
                }
            }
        }
    end

    -- 谜题面板覆盖层
    local puzzleWidget = UI_Puzzle.CreateWidget()
    if puzzleWidget then
        children[#children + 1] = puzzleWidget
    end

    -- 胜利覆盖层
    if gamePhase == "victory" then
        children[#children + 1] = CreateVictoryOverlay(gameData)
    end

    return UI.Panel {
        id = "gameRoot",
        width = "100%",
        height = "100%",
        backgroundColor = { 5, 7, 12, 255 },
        children = children,
    }
end

-- ============================================================================
-- 左侧场景视口（背景图 + 顶栏 + 边缘出口 + 消息）
-- ============================================================================

---@param gameData table
---@param scene table|nil
---@param sceneId string
---@return table
function CreateSceneViewport(gameData, scene, sceneId)
    local bgPath = ""
    if scene and scene.imageUrl and #scene.imageUrl > 0 then
        bgPath = Data.ResolveAssetPath(scene.imageUrl)
    end

    local title = (scene and scene.title) or sceneId

    local overlay = {}

    -- 暗角渐变遮罩（提升文字可读性）
    overlay[#overlay + 1] = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 55 },
        pointerEvents = "none",
    }

    -- 顶部左侧：场景名
    overlay[#overlay + 1] = UI.Panel {
        position = "absolute",
        top = 10, left = 10,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 10, paddingRight = 10,
        paddingTop = 6, paddingBottom = 6,
        backgroundColor = { 0, 0, 0, 150 },
        borderRadius = 8,
        borderWidth = 1,
        borderColor = { 255, 255, 255, 40 },
        children = {
            UI.Label {
                text = title,
                fontSize = 15,
                fontColor = { 235, 235, 245, 255 },
            },
        }
    }

    -- (探索按钮移到底部交互物面板，与 H5 BottomControlPanel 一致)

    -- 边缘出口按钮
    if scene and scene.exits and #scene.exits > 0 then
        local edges = CreateExitEdges(scene.exits)
        for _, w in ipairs(edges) do
            overlay[#overlay + 1] = w
        end
    end

    return UI.Panel {
        id = "sceneViewport",
        flexGrow = 1,
        flexShrink = 1,
        width = "100%",
        position = "relative",
        backgroundColor = { 10, 10, 18, 255 },
        backgroundImage = (#bgPath > 0) and bgPath or nil,
        backgroundFit = "cover",
        children = overlay,
    }
end

-- ============================================================================
-- 边缘出口按钮（north=上, south=下, west=左, east=右）
-- ============================================================================

---@param exits table[]
---@return table[] 绝对定位的出口控件列表
function CreateExitEdges(exits)
    local groups = { top = {}, bottom = {}, left = {}, right = {} }

    for _, exit in ipairs(exits) do
        if not exit.hidden then
            local dir = exit.direction
            local side = "bottom"
            if dir == "north" or dir == "up" then
                side = "top"
            elseif dir == "south" or dir == "down" then
                side = "bottom"
            elseif dir == "west" then
                side = "left"
            elseif dir == "east" then
                side = "right"
            end
            local g = groups[side]
            g[#g + 1] = exit
        end
    end

    local function makeBtn(exit)
        local isLocked = (exit.locked or exit.requiredFlag)
            and exit.requiredFlag and not GameState.GetFlag(exit.requiredFlag)
        local label = exit.label or "前往"
        local directionKind = exit.direction
        if directionKind == "up" then directionKind = "north" end
        if directionKind == "down" then directionKind = "south" end
        local iconColor = isLocked and { 180, 180, 190, 220 } or { 240, 240, 250, 255 }
        local children = {
            GameIcon {
                kind = directionKind,
                width = 28,
                height = 28,
                color = iconColor,
            },
        }
        if isLocked then
            children[#children + 1] = GameIcon {
                kind = "lock",
                width = 22,
                height = 22,
                color = { 245, 193, 67, 255 },
            }
        end
        children[#children + 1] = UI.Label {
            text = label,
            fontSize = 12,
            fontColor = isLocked and { 180, 180, 190, 220 } or { 240, 240, 250, 255 },
            flexShrink = 1,
        }

        return UI.Button {
            text = nil,
            fontSize = 12,
            minWidth = 96,
            paddingLeft = 12, paddingRight = 12,
            height = 44,
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "center",
            gap = 6,
            backgroundColor = { 0, 0, 0, 160 },
            fontColor = isLocked and { 180, 180, 190, 220 } or { 240, 240, 250, 255 },
            borderWidth = 1,
            borderColor = { 255, 255, 255, 70 },
            borderRadius = 8,
            pointerEvents = "auto",
            children = children,
            onClick = function(self)
                GameEngine.HandleMove(exit.targetSceneId, exit.requiredFlag, exit.locked)
            end,
        }
    end

    local widgets = {}

    -- 上方贴顶边
    if #groups.top > 0 then
        local btns = {}
        for _, e in ipairs(groups.top) do btns[#btns + 1] = makeBtn(e) end
        widgets[#widgets + 1] = UI.Panel {
            position = "absolute",
            top = 8, left = 0, right = 0,
            flexDirection = "row",
            justifyContent = "center",
            flexWrap = "wrap",
            gap = 8,
            pointerEvents = "box-none",
            children = btns,
        }
    end

    -- 下方贴底边
    if #groups.bottom > 0 then
        local btns = {}
        for _, e in ipairs(groups.bottom) do btns[#btns + 1] = makeBtn(e) end
        widgets[#widgets + 1] = UI.Panel {
            position = "absolute",
            bottom = 8, left = 0, right = 0,
            flexDirection = "row",
            justifyContent = "center",
            flexWrap = "wrap",
            gap = 8,
            pointerEvents = "box-none",
            children = btns,
        }
    end

    -- 左侧（垂直居中）
    if #groups.left > 0 then
        local btns = {}
        for _, e in ipairs(groups.left) do btns[#btns + 1] = makeBtn(e) end
        widgets[#widgets + 1] = UI.Panel {
            position = "absolute",
            left = 8, top = 0, bottom = 0,
            justifyContent = "center",
            alignItems = "flex-start",
            gap = 8,
            pointerEvents = "box-none",
            children = btns,
        }
    end

    -- 右侧（垂直居中）
    if #groups.right > 0 then
        local btns = {}
        for _, e in ipairs(groups.right) do btns[#btns + 1] = makeBtn(e) end
        widgets[#widgets + 1] = UI.Panel {
            position = "absolute",
            right = 8, top = 0, bottom = 0,
            justifyContent = "center",
            alignItems = "flex-end",
            gap = 8,
            pointerEvents = "box-none",
            children = btns,
        }
    end

    return widgets
end

-- ============================================================================
-- 底部交互物面板
-- ============================================================================

---@param gameData table
---@param scene table|nil
---@return table
function CreateBottomPanel(gameData, scene)
    local interactables = GameEngine.GetInteractablesWithStatus()
    local isExploring = GameEngine.IsExploring()
    local chips = {}
    local hasHiddenItems = false

    for _, entry in ipairs(interactables) do
        local inter = entry.interactable
        local status = entry.status
        local isRevealed = entry.isRevealed

        if not isRevealed then
            hasHiddenItems = true
        end

        -- H5 仅展示已揭示的交互物
        if isRevealed then
            local name = inter.name or inter.id
            local isPuzzle = inter.isPuzzle or inter.puzzleId
            local isAudio = inter.audioMessage
            local isExhausted = (status == "exhausted" or status == "completed")

            local fontColor, bgColor, borderColor
            local prefix = ""
            local locked = false

            if isExhausted then
                fontColor = { 130, 130, 150, 170 }
                bgColor = { 30, 41, 59, 200 }       -- slate-800
                borderColor = { 51, 65, 85, 200 }   -- slate-700
            elseif isAudio then
                fontColor = { 254, 243, 199, 255 }  -- amber-100
                bgColor = { 120, 53, 15, 200 }      -- amber-900/60
                borderColor = { 234, 179, 8, 150 }  -- amber-500/50
                prefix = "[音频] "
            elseif isPuzzle then
                fontColor = { 243, 232, 255, 255 }  -- purple-100
                bgColor = { 88, 28, 135, 200 }      -- purple-900/60
                borderColor = { 168, 85, 247, 150 } -- purple-500/50
                prefix = "[谜题] "
            else
                fontColor = { 209, 250, 229, 255 }  -- emerald-100
                bgColor = { 6, 78, 59, 200 }        -- emerald-900/60
                borderColor = { 16, 185, 129, 150 } -- emerald-500/50
            end

            -- 锁定只显示像素锁，不再写“锁定”
            if inter.requiredItemId and not isExhausted then
                local implicitUnlockFlag = "unlocked_" .. GameState.ResolveActiveSceneId() .. "_" .. inter.id
                local isExplicitlyUnlocked = inter.flagReward and GameState.GetFlag(inter.flagReward)
                local isAlreadyUnlocked = isExplicitlyUnlocked or GameState.GetFlag(implicitUnlockFlag)
                if not isAlreadyUnlocked then
                    locked = true
                end
            end

            local children = {}
            if locked then
                children[#children + 1] = GameIcon {
                    kind = "lock",
                    width = 22,
                    height = 22,
                    color = { 245, 193, 67, 255 },
                }
            end
            children[#children + 1] = UI.Label {
                text = prefix .. name,
                fontSize = 14,
                fontColor = fontColor,
            }

            chips[#chips + 1] = UI.Button {
                text = nil,
                fontSize = 14,
                height = 42,
                paddingLeft = 16, paddingRight = 16,
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "center",
                gap = 6,
                variant = "default",
                textAlign = "center",
                backgroundColor = bgColor,
                fontColor = fontColor,
                borderColor = borderColor,
                borderWidth = 1,
                borderRadius = 10,
                children = children,
                onClick = function(self)
                    GameEngine.HandleInteract(inter)
                end,
            }
        end
    end

    -- 探索/搜查按钮（H5: 在交互物行末尾，有隐藏物品时显示）
    if hasHiddenItems then
        chips[#chips + 1] = UI.Button {
            text = nil,
            fontSize = 14,
            height = 50,
            paddingLeft = 16, paddingRight = 16,
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "center",
            gap = 8,
            variant = "default",
            backgroundColor = isExploring and { 127, 29, 29, 160 } or { 120, 53, 15, 100 },
            fontColor = isExploring and { 252, 165, 165, 255 } or { 245, 158, 11, 255 },
            borderColor = isExploring and { 239, 68, 68, 150 } or { 234, 179, 8, 130 },
            borderWidth = 1,
            borderRadius = 10,
            children = {
                GameIcon {
                    kind = "search",
                    angle = isExploring and searchIconAngle_ or 0,
                    animating = isExploring,
                    width = 32,
                    height = 32,
                    color = isExploring and { 252, 165, 165, 255 } or { 245, 158, 11, 255 },
                },
                UI.Label {
                    text = isExploring and "停止搜查" or "自动搜查",
                    fontSize = 14,
                    fontColor = isExploring and { 252, 165, 165, 255 } or { 245, 158, 11, 255 },
                },
            },
            onClick = function(self)
                GameEngine.ToggleExploration()
            end,
        }
    end

    -- 无可交互物且无隐藏物品
    if #chips == 0 then
        chips[#chips + 1] = UI.Label {
            text = "无可互动物体",
            fontSize = 12,
            fontColor = { 110, 110, 130, 180 },
        }
    end

    local logs = GameState.GetLog() or {}
    local isTyping = UI_Message.IsPlaying()
    local logChildren = {}
    if #logs == 0 then
        logChildren[#logChildren + 1] = UI.Label {
            text = "等待行动...",
            fontSize = 12,
            fontColor = { 90, 100, 120, 180 },
        }
    else
        for i = 1, #logs do
            local isLast = (i == #logs)
            logChildren[#logChildren + 1] = UI.Label {
                text = (isLast and (isTyping and "> " or "* ") or "") .. logs[i],
                fontSize = 12,
                fontColor = isLast and { 251, 191, 36, 255 } or { 148, 163, 184, 160 },
                width = "100%",
                lineHeight = 1.4,
                whiteSpace = "normal",
                wordBreak = "break-word",
            }
        end
        if isTyping then
            logChildren[#logChildren + 1] = UI.Label {
                text = "点击继续",
                fontSize = 11,
                fontColor = { 251, 191, 36, 200 },
                width = "100%",
                textAlign = "right",
            }
        end
    end

    local hintButton = UI.Button {
        text = nil,
        fontSize = 12,
        height = 44,
        flexShrink = 0,
        paddingLeft = 12, paddingRight = 12,
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        backgroundColor = { 15, 23, 42, 230 },
        fontColor = { 203, 213, 225, 255 },
        borderColor = { 71, 85, 105, 200 },
        borderWidth = 1,
        borderRadius = 8,
        children = {
            GameIcon { kind = "hint", width = 28, height = 28, color = { 245, 193, 67, 255 } },
            UI.Label { text = "提示 " .. tostring(Hint.GetRemaining()), fontSize = 12, fontColor = { 203, 213, 225, 255 } },
        },
        onClick = function(self)
            Hint.Request()
        end,
    }

    local centerButtons = UI.Panel {
        flexGrow = 1,
        flexShrink = 1,
        minWidth = 0,
        flexDirection = "row",
        flexWrap = "wrap",
        justifyContent = "center",
        alignItems = "center",
        gap = 8,
        children = chips,
    }

    local collapseButton = UI.Button {
        text = nil,
        fontSize = 12,
        height = 44,
        flexShrink = 0,
        paddingLeft = 12, paddingRight = 12,
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        backgroundColor = { 15, 23, 42, 230 },
        fontColor = { 203, 213, 225, 255 },
        borderColor = { 71, 85, 105, 200 },
        borderWidth = 1,
        borderRadius = 8,
        children = {
            GameIcon {
                kind = logExpanded_ and "collapse" or "expand",
                width = 28,
                height = 28,
                color = { 203, 213, 225, 255 },
            },
            UI.Label {
                text = logExpanded_ and "收起" or "展开",
                fontSize = 12,
                fontColor = { 203, 213, 225, 255 },
            },
        },
        onClick = function(self)
            logExpanded_ = not logExpanded_
            if RefreshGameUI then RefreshGameUI() end
        end,
    }

    return UI.Panel {
        id = "bottomPanel",
        width = "100%",
        flexShrink = 0,
        backgroundColor = { 15, 23, 42, 255 },
        borderTopWidth = 1,
        borderColor = { 51, 65, 85, 160 },
        children = {
            UI.Panel {
                width = "100%",
                paddingTop = 8, paddingBottom = 8,
                paddingLeft = 12, paddingRight = 12,
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                children = { hintButton, centerButtons, collapseButton },
            },
            bindDragScroll(UI.ScrollView {
                id = "logPanel",
                width = "100%",
                height = logExpanded_ and 160 or 72,
                flexShrink = 0,
                backgroundColor = { 0, 0, 0, 242 },
                paddingTop = 10,
                paddingRight = 12,
                paddingBottom = 24,
                paddingLeft = 12,
                scrollY = true,
                showScrollbar = true,
                pointerEvents = "auto",
                onClick = nil,
                children = {
                    UI.Panel {
                        width = "100%",
                        paddingRight = 8,
                        paddingBottom = 20,
                        gap = 6,
                        children = logChildren,
                    }
                }
            }, function()
                if UI_Message.IsPlaying() then
                    UI_Message.Advance()
                end
            end),
        }
    }
end

-- ============================================================================
-- 右侧背包栏（物品 PNG 缩略图竖排）
-- ============================================================================

---@param gameData table
---@return table
function CreateInventorySidebar(gameData)
    local inventory = GameState.GetInventory()
    local selectedId = GameEngine.GetSelectedItemId()

    -- 背包头部
    local header = UI.Panel {
        width = "100%",
        paddingTop = 10, paddingBottom = 8,
        backgroundColor = { 0, 0, 0, 120 },
        borderBottomWidth = 1,
        borderColor = { 51, 65, 85, 160 },
        alignItems = "center",
        gap = 2,
        children = {
            UI.Label {
                text = "背包",
                fontSize = 14,
                fontColor = { 230, 230, 240, 255 },
            },
        }
    }

    -- 物品列表
    local itemWidgets = {}
    if #inventory == 0 then
        itemWidgets[#itemWidgets + 1] = UI.Label {
            text = "空",
            fontSize = 12,
            fontColor = { 90, 95, 115, 200 },
            marginTop = 20,
            alignSelf = "center",
        }
    else
        for _, itemId in ipairs(inventory) do
            local item = gameData.items[itemId]
            if item then
                local isSelected = (itemId == selectedId)
                local imgPath = ""
                if item.image and #item.image > 0 then
                    imgPath = Data.ResolveAssetPath(item.image)
                elseif item.imageUrl and #item.imageUrl > 0 then
                    imgPath = Data.ResolveAssetPath(item.imageUrl)
                end

                -- 缩略图区（PNG 优先，无图回退 emoji）
                local thumbChildren = {}
                if imgPath == "" then
                    thumbChildren[#thumbChildren + 1] = UI.Label {
                        text = item.icon or "物品",
                        fontSize = 28,
                        alignSelf = "center",
                    }
                end

                itemWidgets[#itemWidgets + 1] = UI.Panel {
                    width = "100%",
                    aspectRatio = 1,
                    borderRadius = 10,
                    borderWidth = isSelected and 2 or 1,
                    borderColor = isSelected and { 245, 158, 11, 255 } or { 71, 85, 105, 200 },
                    backgroundColor = isSelected and { 60, 45, 10, 220 } or { 30, 41, 59, 220 },
                    backgroundImage = (imgPath ~= "") and imgPath or nil,
                    backgroundFit = "contain",
                    position = "relative",
                    cursor = "pointer",
                    onClick = function(self)
                        if selectedId == itemId then
                            -- 已选中再点 → 打开查看详情（H5: inspectingItem）
                            inspectingItemId_ = itemId
                            GameEngine.ClearSelectedItem()
                        else
                            -- 首次点击 → 选中
                            GameEngine.SetSelectedItem(itemId)
                        end
                        if RefreshGameUI then RefreshGameUI() end
                    end,
                    children = {
                        -- emoji 回退（仅无图时）
                        table.unpack(thumbChildren),
                        -- 物品名标签（底部）
                        UI.Panel {
                            position = "absolute",
                            left = 2, right = 2, bottom = 2,
                            paddingTop = 2, paddingBottom = 2,
                            backgroundColor = { 0, 0, 0, 200 },
                            borderRadius = 4,
                            children = {
                                UI.Label {
                                    text = item.name,
                                    fontSize = 9,
                                    fontColor = { 230, 230, 240, 255 },
                                    width = "100%",
                                    textAlign = "center",
                                    maxLines = 1,
                                },
                            }
                        },
                    }
                }
            end
        end
    end

    local itemList = UI.ScrollView {
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
        children = {
            UI.Panel {
                width = "100%",
                padding = 6,
                gap = 6,
                children = itemWidgets,
            },
        }
    }

    return UI.Panel {
        id = "inventorySidebar",
        width = INVENTORY_WIDTH,
        height = "100%",
        flexShrink = 0,
        flexDirection = "column",
        backgroundColor = { 12, 16, 26, 255 },
        borderLeftWidth = 1,
        borderColor = { 51, 65, 85, 200 },
        children = { header, itemList },
    }
end

-- ============================================================================
-- 物品查看弹窗（对应 H5 inspectingItem 全屏覆盖层）
-- 显示物品大图 + 名称 + 描述，点击背景关闭
-- ============================================================================

---@param item table
---@return table
function CreateItemInspectModal(item)
    local imgPath = ""
    if item.image and #item.image > 0 then
        imgPath = Data.ResolveAssetPath(item.image)
    elseif item.imageUrl and #item.imageUrl > 0 then
        imgPath = Data.ResolveAssetPath(item.imageUrl)
    end

    -- 图片区或 emoji 回退
    local imageWidget
    if imgPath ~= "" then
        imageWidget = UI.Panel {
            width = "70%",
            aspectRatio = 1,
            maxWidth = 280,
            borderRadius = 20,
            backgroundColor = { 30, 41, 59, 255 },
            borderWidth = 4,
            borderColor = { 51, 65, 85, 200 },
            backgroundImage = imgPath,
            backgroundFit = "contain",
        }
    else
        imageWidget = UI.Panel {
            width = "70%",
            aspectRatio = 1,
            maxWidth = 280,
            borderRadius = 20,
            backgroundColor = { 30, 41, 59, 255 },
            borderWidth = 4,
            borderColor = { 51, 65, 85, 200 },
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Label {
                    text = item.icon or "物品",
                    fontSize = 64,
                },
            }
        }
    end

    local descScroll = bindDragScroll(UI.ScrollView {
        width = "100%",
        height = 160,
        flexShrink = 0,
        scrollY = true,
        showScrollbar = true,
        pointerEvents = "auto",
        children = {
            UI.Panel {
                width = "100%",
                paddingRight = 12,
                paddingBottom = 24,
                children = {
                    UI.Label {
                        text = item.description or "",
                        fontSize = 14,
                        fontColor = { 203, 213, 225, 255 },
                        textAlign = "left",
                        lineHeight = 1.5,
                        width = "100%",
                        whiteSpace = "normal",
                        wordBreak = "break-word",
                    },
                }
            }
        }
    })

    return UI.Panel {
        id = "itemInspectOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 230 },
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "auto",
        onClick = function(self)
            UI_Game.CloseInspect()
        end,
        children = {
            UI.Panel {
                width = "85%",
                maxWidth = 400,
                maxHeight = "88%",
                padding = 20,
                gap = 12,
                alignItems = "stretch",
                pointerEvents = "auto",
                onClick = function(self)
                    -- 阻止冒泡到背景（点内容不关闭）
                end,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        alignItems = "center",
                        justifyContent = "space-between",
                        children = {
                            UI.Label {
                                text = "物品详情",
                                fontSize = 12,
                                fontColor = { 148, 163, 184, 255 },
                            },
                            UI.Button {
                                text = "关闭",
                                height = 32,
                                paddingLeft = 12,
                                paddingRight = 12,
                                fontSize = 12,
                                variant = "ghost",
                                fontColor = { 226, 232, 240, 255 },
                                onClick = function(self)
                                    UI_Game.CloseInspect()
                                end,
                            },
                        }
                    },
                    UI.Panel {
                        width = "100%",
                        alignItems = "center",
                        children = { imageWidget },
                    },
                    UI.Label {
                        text = item.name or "未知物品",
                        fontSize = 20,
                        fontColor = { 245, 158, 11, 255 },
                        textAlign = "center",
                        width = "100%",
                    },
                    descScroll,
                }
            }
        }
    }
end

-- ============================================================================
-- 胜利覆盖层
-- ============================================================================

---@param gameData table
---@return table
function CreateVictoryOverlay(gameData)
    local meta = gameData.meta or {}

    return UI.Panel {
        id = "victoryOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 200 },
        pointerEvents = "auto",
        children = {
            UI.Panel {
                width = "80%",
                maxWidth = 360,
                padding = 32,
                gap = 16,
                backgroundColor = { 15, 25, 15, 240 },
                borderRadius = 20,
                borderWidth = 2,
                borderColor = { 80, 180, 80, 150 },
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "通关",
                        fontSize = 28,
                        fontColor = { 250, 204, 21, 255 },
                    },
                    UI.Label {
                        text = "恭喜通关！",
                        fontSize = 22,
                        fontColor = { 120, 255, 120, 255 },
                        textAlign = "center",
                    },
                    UI.Label {
                        text = meta.name or "游戏",
                        fontSize = 14,
                        fontColor = { 180, 220, 180, 200 },
                        textAlign = "center",
                    },
                    UI.Panel {
                        width = "60%",
                        height = 1,
                        backgroundColor = { 80, 180, 80, 80 },
                        marginTop = 4,
                        marginBottom = 4,
                    },
                    UI.Button {
                        text = "再玩一次",
                        variant = "primary",
                        paddingLeft = 24,
                        paddingRight = 24,
                        onClick = function(self)
                            OnGameRestart()
                        end,
                    },
                    UI.Button {
                        text = "选择其他故事",
                        variant = "ghost",
                        fontSize = 13,
                        onClick = function(self)
                            ShowGameSelectScreen()
                        end,
                    },
                }
            }
        }
    }
end

return UI_Game
