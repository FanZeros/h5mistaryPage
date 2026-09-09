-- ============================================================================
-- UI_GameSelect.lua - 游戏选择画面
-- 对应 H5: GameSelector.tsx (画廊式游戏选择)
-- ============================================================================

local UI = require("urhox-libs/UI")
local Storage = require("Storage")
local Ads = require("Ads")

local UI_GameSelect = {}

-- ============================================================================
-- 创建游戏选择画面
-- ============================================================================

--- 创建游戏选择 UI
---@param gameList table 游戏列表数组 (来自 games.json)
---@param onSelect function(gameEntry) 选择游戏回调
---@return table UI root widget
function UI_GameSelect.Create(gameList, onSelect)
    ---@type Widget|nil
    local noticeLabel = UI.Label {
        id = "selectNotice",
        text = "",
        fontSize = 11,
        fontColor = { 255, 190, 160, 255 },
        height = 16,
    }

    local function setNotice(msg)
        if noticeLabel and noticeLabel.SetText then
            noticeLabel:SetText(msg or "")
        end
    end

    -- 构建游戏卡片列表
    local cards = {}
    for i, game in ipairs(gameList) do
        local isFree = game.free == true
        local unlocked = Storage.IsGameUnlocked(game.id, isFree)
        -- 时长/房间数标签
        local infoText = ""
        if game.duration then
            infoText = infoText .. game.duration
        end
        if game.rooms and game.rooms > 0 then
            infoText = infoText .. " · " .. game.rooms .. "个房间"
        end

        cards[#cards + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            padding = 10,
            gap = 12,
            backgroundColor = { 25, 25, 40, 220 },
            borderRadius = 12,
            borderWidth = 1,
            borderColor = isFree and { 60, 160, 80, 150 } or (unlocked and { 90, 70, 160, 150 } or { 50, 50, 80, 100 }),
            alignItems = "center",
            cursor = "pointer",
            onClick = function(self)
                print("[GameSelect] Selected: " .. game.name .. " (" .. game.id .. ")")
                if unlocked then
                    if onSelect then
                        onSelect(game)
                    end
                    return
                end
                if Ads.IsInFlight() then
                    return
                end
                Ads.ShowReward(function()
                    Storage.UnlockGame(game.id)
                    if onSelect then
                        onSelect(game)
                    end
                end, function()
                    print("[GameSelect] unlock ad failed for " .. tostring(game.id))
                    setNotice("广告未完成，未解锁该故事")
                end)
            end,
            children = {
                -- 游戏图标
                UI.Panel {
                    width = 56,
                    height = 56,
                    borderRadius = 10,
                    backgroundColor = { 40, 40, 60, 200 },
                    backgroundImage = (game.icon and #game.icon > 0) and game.icon or nil,
                    backgroundFit = "cover",
                    flexShrink = 0,
                },
                -- 文字信息区
                UI.Panel {
                    flexGrow = 1,
                    flexShrink = 1,
                    gap = 3,
                    children = {
                        -- 标题行 (名称 + 免费标签)
                        UI.Panel {
                            flexDirection = "row",
                            alignItems = "center",
                            gap = 6,
                            children = {
                                UI.Label {
                                    text = game.name or "未命名",
                                    fontSize = 15,
                                    fontColor = { 240, 240, 255, 255 },
                                    flexShrink = 1,
                                },
                                isFree and UI.Panel {
                                    paddingLeft = 6,
                                    paddingRight = 6,
                                    paddingTop = 2,
                                    paddingBottom = 2,
                                    backgroundColor = { 30, 120, 50, 200 },
                                    borderRadius = 4,
                                    children = {
                                        UI.Label {
                                            text = "免费",
                                            fontSize = 10,
                                            fontColor = { 150, 255, 150, 255 },
                                        },
                                    },
                                } or (unlocked and UI.Panel {
                                    paddingLeft = 6,
                                    paddingRight = 6,
                                    paddingTop = 2,
                                    paddingBottom = 2,
                                    backgroundColor = { 70, 50, 140, 200 },
                                    borderRadius = 4,
                                    children = {
                                        UI.Label {
                                            text = "已解锁",
                                            fontSize = 10,
                                            fontColor = { 210, 190, 255, 255 },
                                        },
                                    },
                                } or UI.Panel {
                                    paddingLeft = 6,
                                    paddingRight = 6,
                                    paddingTop = 2,
                                    paddingBottom = 2,
                                    backgroundColor = { 90, 40, 40, 200 },
                                    borderRadius = 4,
                                    children = {
                                        UI.Label {
                                            text = "看广告解锁",
                                            fontSize = 10,
                                            fontColor = { 255, 190, 160, 255 },
                                        },
                                    },
                                }),
                            },
                        },
                        -- 描述
                        UI.Label {
                            text = game.description or "",
                            fontSize = 11,
                            fontColor = { 140, 140, 170, 200 },
                            lineHeight = 1.3,
                            maxLines = 2,
                        },
                        -- 信息标签
                        UI.Label {
                            text = infoText,
                            fontSize = 10,
                            fontColor = { 100, 130, 160, 180 },
                            marginTop = 2,
                        },
                    },
                },
                -- 右侧箭头
                UI.Label {
                    text = ">",
                    fontSize = 14,
                    fontColor = { 100, 100, 140, 150 },
                    flexShrink = 0,
                },
            },
        }
    end

    -- 整体布局
    local root = UI.Panel {
        id = "gameSelectRoot",
        width = "100%",
        height = "100%",
        backgroundColor = { 8, 8, 16, 255 },
        children = {
            -- 顶部标题栏
            UI.Panel {
                width = "100%",
                padding = 16,
                paddingTop = 20,
                paddingBottom = 12,
                alignItems = "center",
                gap = 4,
                children = {
                    UI.Label {
                        text = "迷境探索",
                        fontSize = 22,
                        fontColor = { 200, 180, 255, 255 },
                    },
                    UI.Label {
                        text = "选择一个故事开始探索",
                        fontSize = 12,
                        fontColor = { 120, 120, 160, 200 },
                    },
                    -- 游戏数量
                    UI.Label {
                        text = #gameList .. " 个故事可供探索",
                        fontSize = 10,
                        fontColor = { 80, 100, 130, 150 },
                        marginTop = 4,
                    },
                    noticeLabel,
                },
            },
            -- 分隔线
            UI.Panel {
                width = "90%",
                height = 1,
                backgroundColor = { 50, 50, 80, 80 },
                alignSelf = "center",
            },
            -- 可滚动的游戏列表
            UI.ScrollView {
                width = "100%",
                flexGrow = 1,
                flexShrink = 1,
                children = {
                    UI.Panel {
                        width = "100%",
                        padding = 12,
                        gap = 10,
                        children = cards,
                    },
                },
            },
        },
    }

    return root
end

return UI_GameSelect
