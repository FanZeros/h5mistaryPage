-- ============================================================================
-- UI_Puzzle.lua - 谜题面板
-- 对应 H5: puzzleModal + 数字/符号/文本输入 + image_grid + one_line
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameEngine = require("GameEngine")
local Audio = require("Audio")

---@type fun()
RefreshGameUI = RefreshGameUI
---@type fun(): table|nil
GetGameData = GetGameData

local UI_Puzzle = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

local isOpen_ = false
local puzzleId_ = nil
local interactableId_ = nil
local inputText_ = ""
local gameData_ = nil
local hintText_ = ""
local hintIsError_ = false

-- ============================================================================
-- 初始化
-- ============================================================================

function UI_Puzzle.Init()
    isOpen_ = false
    puzzleId_ = nil
    interactableId_ = nil
    inputText_ = ""
    hintText_ = ""
    hintIsError_ = false
end

-- ============================================================================
-- 公共 API
-- ============================================================================

function UI_Puzzle.IsOpen()
    return isOpen_
end

function UI_Puzzle.Open(puzzleId, interactableId)
    puzzleId_ = puzzleId
    interactableId_ = interactableId
    inputText_ = ""
    hintText_ = ""
    hintIsError_ = false
    isOpen_ = true
    print("[Puzzle] Opened: " .. tostring(puzzleId))
    if RefreshGameUI then RefreshGameUI() end
end

function UI_Puzzle.Close()
    isOpen_ = false
    puzzleId_ = nil
    interactableId_ = nil
    inputText_ = ""
    hintText_ = ""
    hintIsError_ = false
    if RefreshGameUI then RefreshGameUI() end
end

function UI_Puzzle.GetCurrentPuzzle()
    if not puzzleId_ then return nil end
    local gd = GetGameData()
    if not gd then return nil end
    return gd.puzzles[puzzleId_]
end

-- ============================================================================
-- 输入处理
-- ============================================================================

local function handleCharInput(char)
    Audio.PlaySound("click")
    hintText_ = ""
    hintIsError_ = false
    if char == "C" or char == "CLR" then
        inputText_ = ""
    elseif char == "⌫" or char == "←" or char == "DEL" then
        -- UTF-8 aware backspace
        if #inputText_ > 0 then
            -- 简单处理：移除最后一个字符（UTF-8 多字节）
            local bytes = { inputText_:byte(1, #inputText_) }
            local i = #bytes
            while i > 0 and bytes[i] >= 128 and bytes[i] < 192 do
                i = i - 1
            end
            if i > 0 then
                inputText_ = inputText_:sub(1, i - 1)
            end
        end
    else
        if #inputText_ < 20 then
            inputText_ = inputText_ .. char
        end
    end
    if RefreshGameUI then RefreshGameUI() end
end

local function handleSubmit()
    if not puzzleId_ or #inputText_ == 0 then
        hintText_ = "请先输入答案"
        hintIsError_ = true
        if RefreshGameUI then RefreshGameUI() end
        return
    end
    local success, resultMessage = GameEngine.HandlePuzzleSubmit(puzzleId_, interactableId_, inputText_)
    if success then
        UI_Puzzle.Close()
    else
        inputText_ = ""
        hintText_ = resultMessage or "错误：解答不正确。"
        hintIsError_ = true
        if RefreshGameUI then RefreshGameUI() end
    end
end

-- ============================================================================
-- UI 构建
-- ============================================================================

--- 创建数字键盘
local function CreateNumericKeypad()
    local rows = {
        { "1", "2", "3" },
        { "4", "5", "6" },
        { "7", "8", "9" },
        { "CLR", "0", "DEL" },
    }
    local children = {}
    for _, row in ipairs(rows) do
        local rowChildren = {}
        for _, key in ipairs(row) do
            rowChildren[#rowChildren + 1] = UI.Button {
                text = key,
                width = 56,
                height = 44,
                fontSize = 18,
                variant = (key == "CLR" or key == "DEL" or key == "C" or key == "←") and "secondary" or "default",
                onClick = function(self)
                    handleCharInput(key)
                end,
            }
        end
        children[#children + 1] = UI.Panel {
            flexDirection = "row",
            gap = 8,
            justifyContent = "center",
            children = rowChildren,
        }
    end
    return UI.Panel {
        gap = 8,
        alignItems = "center",
        children = children,
    }
end

--- 创建符号选择按钮
local function CreateSymbolButtons(choices)
    if not choices or #choices == 0 then return nil end
    local rowChildren = {}
    for _, symbol in ipairs(choices) do
        rowChildren[#rowChildren + 1] = UI.Button {
            text = symbol,
            width = 48,
            height = 44,
            fontSize = 16,
            onClick = function(self)
                handleCharInput(symbol)
            end,
        }
    end
    -- 添加清除和退格
    rowChildren[#rowChildren + 1] = UI.Button {
        text = "DEL",
        width = 48,
        height = 44,
        fontSize = 14,
        variant = "secondary",
        onClick = function(self)
            handleCharInput("DEL")
        end,
    }
    rowChildren[#rowChildren + 1] = UI.Button {
        text = "C",
        width = 48,
        height = 44,
        fontSize = 16,
        variant = "secondary",
        onClick = function(self)
            handleCharInput("C")
        end,
    }
    return UI.Panel {
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 6,
        justifyContent = "center",
        children = rowChildren,
    }
end

--- 创建文本输入区
local function CreateTextInput()
    return UI.Panel {
        width = "100%",
        gap = 8,
        alignItems = "center",
        children = {
            UI.TextField {
                id = "puzzleTextField",
                placeholder = "输入答案...",
                value = inputText_,
                width = "90%",
                fontSize = 16,
                onChange = function(self, text)
                    inputText_ = text
                end,
                onSubmit = function(self, text)
                    inputText_ = text
                    handleSubmit()
                end,
            },
        }
    }
end

--- 创建谜题面板主体
---@return table|nil
function UI_Puzzle.CreateWidget()
    if not isOpen_ then return nil end

    local puzzle = UI_Puzzle.GetCurrentPuzzle()
    if not puzzle then
        UI_Puzzle.Close()
        return nil
    end

    -- 输入区域
    local inputWidget = nil
    if puzzle.type == "numeric" then
        inputWidget = CreateNumericKeypad()
    elseif puzzle.type == "symbol" then
        inputWidget = CreateSymbolButtons(puzzle.choices)
    elseif puzzle.type == "image_grid" then
        -- 图片拼图类型：暂以文本提示方式呈现
        inputWidget = UI.Panel {
            width = "100%",
            gap = 8,
            alignItems = "center",
            children = {
                UI.Label {
                    text = "图片拼图",
                    fontSize = 16,
                    fontColor = { 200, 180, 255, 255 },
                },
                UI.Label {
                    text = "请观察图片碎片的正确顺序，输入还原序号",
                    fontSize = 12,
                    fontColor = { 150, 150, 170, 200 },
                    textAlign = "center",
                    lineHeight = 1.4,
                },
                CreateTextInput(),
            }
        }
    elseif puzzle.type == "one_line" then
        -- 一笔画类型：暂以文本提示方式呈现
        inputWidget = UI.Panel {
            width = "100%",
            gap = 8,
            alignItems = "center",
            children = {
                UI.Label {
                    text = "一笔画谜题",
                    fontSize = 16,
                    fontColor = { 200, 180, 255, 255 },
                },
                UI.Label {
                    text = "按顺序输入经过的节点编号，用逗号分隔",
                    fontSize = 12,
                    fontColor = { 150, 150, 170, 200 },
                    textAlign = "center",
                    lineHeight = 1.4,
                },
                CreateTextInput(),
            }
        }
    else
        -- text 或其他类型
        inputWidget = CreateTextInput()
    end

    return UI.Panel {
        id = "puzzleOverlay",
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        pointerEvents = "auto",
        onClick = function(self)
            -- 点击背景关闭
            UI_Puzzle.Close()
        end,
        children = {
            UI.ScrollView {
                width = "90%",
                maxWidth = 380,
                maxHeight = "88%",
                backgroundColor = { 30, 30, 40, 245 },
                borderRadius = 16,
                borderWidth = 1,
                borderColor = { 80, 80, 120, 150 },
                pointerEvents = "auto",
                onClick = function(self)
                    -- 阻止冒泡到背景
                end,
                children = {
                    UI.Panel {
                        width = "100%",
                        padding = 24,
                        gap = 16,
                        flexShrink = 1,
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = puzzle.description or "解开谜题",
                                fontSize = 14,
                                fontColor = { 200, 200, 220, 255 },
                                width = "100%",
                                textAlign = "center",
                                lineHeight = 1.4,
                            },
                            UI.Panel {
                                width = "100%",
                                padding = 12,
                                backgroundColor = { 20, 20, 30, 255 },
                                borderRadius = 8,
                                borderWidth = 1,
                                borderColor = { 60, 60, 80, 200 },
                                minHeight = 40,
                                justifyContent = "center",
                                alignItems = "center",
                                children = {
                                    UI.Label {
                                        text = #inputText_ > 0 and inputText_ or "...",
                                        fontSize = 20,
                                        fontColor = #inputText_ > 0 and { 255, 255, 255, 255 } or { 100, 100, 100, 150 },
                                        textAlign = "center",
                                    },
                                }
                            },
                            inputWidget,
                            UI.Panel {
                                id = "puzzleHintWrap",
                                width = "100%",
                                padding = 10,
                                backgroundColor = hintIsError_ and { 80, 20, 20, 220 } or { 20, 30, 50, 180 },
                                borderRadius = 8,
                                borderWidth = 1,
                                borderColor = hintIsError_ and { 220, 80, 80, 180 } or { 80, 100, 140, 120 },
                                visible = hintText_ ~= "",
                                children = {
                                    UI.Label {
                                        id = "puzzleHintText",
                                        text = hintText_,
                                        fontSize = 13,
                                        fontColor = hintIsError_ and { 255, 200, 200, 255 } or { 210, 220, 240, 255 },
                                        width = "100%",
                                        textAlign = "center",
                                        lineHeight = 1.4,
                                    },
                                },
                            },
                            UI.Button {
                                text = "确认",
                                variant = "primary",
                                width = "80%",
                                onClick = function(self)
                                    handleSubmit()
                                end,
                            },
                            UI.Button {
                                text = "返回",
                                variant = "ghost",
                                fontSize = 13,
                                onClick = function(self)
                                    UI_Puzzle.Close()
                                end,
                            },
                        }
                    },
                }
            }
        }
    }
end

return UI_Puzzle
