-- ============================================================================
-- UI_Title.lua - 标题画面
-- 对应 H5: TitleScreen 组件
-- ============================================================================

local UI = require("urhox-libs/UI")
local Data = require("Data")

---@type fun()
ShowGameSelectScreen = ShowGameSelectScreen

local UI_Title = {}

-- ============================================================================
-- 创建标题画面
-- ============================================================================

--- 创建标题画面 UI 树
---@param gameData table 游戏数据
---@param onStart function(difficulty) 开始游戏回调
---@param options table|nil { restTotal: number }
---@return table UI root widget
function UI_Title.Create(gameData, onStart, options)
    local meta = gameData.meta or {}
    local marketing = gameData.marketing or {}
    options = options or {}
    local restTotal = options.restTotal or 0
    local restLoading = restTotal > 0

    -- 背景图片路径：优先 marketing.bannerUrl，其次 meta.banner，再回退到游戏目录默认封面
    local bgPath = ""
    local bannerCandidates = {
        marketing.bannerUrl,
        meta.banner,
    }
    for _, raw in ipairs(bannerCandidates) do
        if raw and #raw > 0 then
            local resolved = Data.ResolveAssetPath(raw)
            if resolved ~= "" then
                bgPath = resolved
                break
            end
        end
    end
    if bgPath == "" and Data.currentGameBaseDir and Data.currentGameBaseDir ~= "" then
        local fallbacks = {
            Data.currentGameBaseDir .. "game_banner_1080.jpg",
            Data.currentGameBaseDir .. "marketing_banner.jpg",
            Data.currentGameBaseDir .. "banner.jpg",
        }
        for _, candidate in ipairs(fallbacks) do
            if cache:Exists(candidate) then
                bgPath = candidate
                break
            end
        end
    end

    -- 构建 UI
    local root = UI.Panel {
        id = "titleRoot",
        width = "100%",
        height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 10, 10, 20, 255 },
        backgroundImage = (#bgPath > 0) and bgPath or nil,
        backgroundSize = "cover",
        children = {
            -- 半透明遮罩
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                backgroundColor = { 0, 0, 0, 120 },
                pointerEvents = "none",
            },
            -- 内容卡片
            UI.Panel {
                width = "85%",
                maxWidth = 380,
                padding = 32,
                gap = 16,
                backgroundColor = { 15, 15, 25, 220 },
                borderRadius = 20,
                borderWidth = 1,
                borderColor = { 60, 60, 90, 100 },
                alignItems = "center",
                children = {
                    -- 游戏标题
                    UI.Label {
                        text = meta.name or "迷境探索",
                        fontSize = 26,
                        fontColor = { 255, 255, 255, 255 },
                        textAlign = "center",
                    },
                    -- 作者
                    UI.Label {
                        text = (meta.author and #meta.author > 0) and ("by " .. meta.author) or "",
                        fontSize = 12,
                        fontColor = { 150, 150, 180, 200 },
                        textAlign = "center",
                    },
                    -- 描述
                    UI.Label {
                        text = meta.description or "",
                        fontSize = 13,
                        fontColor = { 180, 180, 200, 220 },
                        textAlign = "center",
                        lineHeight = 1.5,
                        marginTop = 8,
                        marginBottom = 8,
                    },
                    -- 分割线
                    UI.Panel {
                        width = "60%",
                        height = 1,
                        backgroundColor = { 80, 80, 120, 100 },
                        marginTop = 4,
                        marginBottom = 4,
                    },
                    -- 难度选择
                    UI.Label {
                        text = "选择难度",
                        fontSize = 12,
                        fontColor = { 130, 130, 160, 180 },
                    },
                    -- 按钮组
                    UI.Panel {
                        flexDirection = "row",
                        gap = 12,
                        children = {
                            UI.Button {
                                id = "titleEasyBtn",
                                text = restLoading and "加载中" or "简单",
                                disabled = restLoading,
                                paddingLeft = 20,
                                paddingRight = 20,
                                backgroundColor = { 20, 80, 40, 200 },
                                borderColor = { 60, 180, 80, 200 },
                                borderWidth = 1,
                                borderRadius = 8,
                                fontColor = { 120, 240, 120, 255 },
                                onClick = function(self)
                                    onStart("EASY")
                                end,
                            },
                            UI.Button {
                                id = "titleStandardBtn",
                                text = restLoading and "加载中" or "标准",
                                disabled = restLoading,
                                paddingLeft = 20,
                                paddingRight = 20,
                                backgroundColor = { 80, 50, 10, 200 },
                                borderColor = { 200, 150, 50, 200 },
                                borderWidth = 1,
                                borderRadius = 8,
                                fontColor = { 255, 200, 100, 255 },
                                onClick = function(self)
                                    onStart("STANDARD")
                                end,
                            },
                        }
                    },
                    -- 返回游戏列表
                    UI.Button {
                        text = "选择其他故事",
                        variant = "ghost",
                        fontSize = 11,
                        fontColor = { 120, 120, 160, 180 },
                        marginTop = 8,
                        onClick = function(self)
                            ShowGameSelectScreen()
                        end,
                    },
                    -- 版本号
                    UI.Label {
                        text = "v" .. (meta.version or "1.0.0"),
                        fontSize = 10,
                        fontColor = { 100, 100, 120, 120 },
                        marginTop = 4,
                    },
                    -- 后台资源加载进度（场景图/物品图）
                    UI.Panel {
                        id = "titleLoadingWrap",
                        width = "100%",
                        marginTop = 8,
                        gap = 6,
                        alignItems = "center",
                        visible = restLoading,
                        children = {
                            UI.Label {
                                id = "titleLoadingText",
                                text = restLoading and ("正在加载场景资源 0 / " .. restTotal) or "资源已就绪",
                                fontSize = 11,
                                fontColor = { 180, 160, 90, 220 },
                                textAlign = "center",
                            },
                            UI.Panel {
                                width = "80%",
                                height = 6,
                                backgroundColor = { 30, 41, 59, 255 },
                                borderRadius = 3,
                                overflow = "hidden",
                                children = {
                                    UI.Panel {
                                        id = "titleLoadingBar",
                                        width = "4%",
                                        height = "100%",
                                        backgroundColor = { 245, 158, 11, 255 },
                                        borderRadius = 3,
                                    },
                                },
                            },
                        },
                    },
                }
            }
        }
    }

    return root
end

return UI_Title
