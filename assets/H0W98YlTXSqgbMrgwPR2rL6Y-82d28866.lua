-- ============================================================================
-- UI_Puzzle.lua - 谜题面板
-- 对应 H5: puzzleModal + 数字/符号/文本输入 + image_grid + one_line
-- ============================================================================

local UI = require("urhox-libs/UI")
local Widget = require("urhox-libs/UI/Core/Widget")
local GameEngine = require("GameEngine")
local GameState = require("GameState")
local Data = require("Data")
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
---@type number[]
local oneLinePath_ = {}
local oneLineSolved_ = false

local function clearOneLinePath()
    for i = #oneLinePath_, 1, -1 do
        oneLinePath_[i] = nil
    end
    oneLineSolved_ = false
end

---@type number[]
local imageGridTiles_ = {}
---@type number|nil
local imageGridSelected_ = nil
local imageGridSolved_ = false
local imageGridImg_ = -1
local imageGridImgPath_ = ""

local function clearImageGrid()
    for i = #imageGridTiles_, 1, -1 do
        imageGridTiles_[i] = nil
    end
    imageGridSelected_ = nil
    imageGridSolved_ = false
end

local function initImageGrid(gridSize)
    clearImageGrid()
    local count = gridSize * gridSize
    for i = 1, count do
        imageGridTiles_[i] = i - 1
    end
    for i = count, 2, -1 do
        local j = math.random(1, i)
        imageGridTiles_[i], imageGridTiles_[j] = imageGridTiles_[j], imageGridTiles_[i]
    end
    local solved = true
    for i = 1, count do
        if imageGridTiles_[i] ~= (i - 1) then
            solved = false
            break
        end
    end
    if solved and count > 1 then
        imageGridTiles_[1], imageGridTiles_[2] = imageGridTiles_[2], imageGridTiles_[1]
    end
end

local function resolvePuzzleImage(puzzle)
    if not puzzle then
        return ""
    end
    local gd = GetGameData and GetGameData() or nil
    local linked = puzzle.linkedAssetId
    if gd and linked then
        local item = gd.items and gd.items[linked]
        if item then
            local raw = item.image or item.imageUrl
            if raw and #raw > 0 then
                return Data.ResolveAssetPath(raw)
            end
        end
        local scene = gd.scenes and gd.scenes[linked]
        if scene and scene.imageUrl and #scene.imageUrl > 0 then
            return Data.ResolveAssetPath(scene.imageUrl)
        end
    end
    return ""
end

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
    clearOneLinePath()
    clearImageGrid()
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
    clearOneLinePath()
    clearImageGrid()
    local gd = GetGameData and GetGameData() or nil
    local puzzle = gd and gd.puzzles and gd.puzzles[puzzleId]
    if puzzle and puzzle.type == "image_grid" then
        local gridSize = puzzle.gridSize or 3
        if GameState.GetDifficulty() == "STANDARD" then
            gridSize = gridSize + 1
        end
        initImageGrid(gridSize)
    end
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
    clearOneLinePath()
    clearImageGrid()
    if RefreshGameUI then RefreshGameUI() end
end

function UI_Puzzle.GetCurrentPuzzle()
    if not puzzleId_ then return nil end
    local gd = GetGameData()
    if not gd then return nil end
    return gd.puzzles[puzzleId_]
end

-- ============================================================================
-- 一笔画棋盘（对应 H5 OneLinePuzzle）
-- ============================================================================

---@class OneLineBoard : Widget
local OneLineBoard = Widget:Extend("OneLineBoard")

---@param props table
function OneLineBoard:Init(props)
    props = props or {}
    props.width = props.width or 280
    props.height = props.height or 280
    props.flexShrink = 0
    Widget.Init(self, props)
end

local function pathUsesEdge(path, a, b)
    for i = 1, #path - 1 do
        if (path[i] == a and path[i + 1] == b) or (path[i] == b and path[i + 1] == a) then
            return true
        end
    end
    return false
end

local function checkOneLineVictory(path, connections)
    if #path < 2 then
        return false
    end
    local remaining = {}
    local remainingCount = 0
    for _, c in ipairs(connections) do
        remainingCount = remainingCount + 1
        remaining[remainingCount] = { math.min(c[1], c[2]), math.max(c[1], c[2]) }
    end
    for i = 1, #path - 1 do
        local lo = math.min(path[i], path[i + 1])
        local hi = math.max(path[i], path[i + 1])
        local found = false
        for j = 1, remainingCount do
            local e = remaining[j]
            if e[1] == lo and e[2] == hi then
                remaining[j] = remaining[remainingCount]
                remaining[remainingCount] = nil
                remainingCount = remainingCount - 1
                found = true
                break
            end
        end
        if not found then
            return false
        end
    end
    return remainingCount == 0
end

---@param nvg NVGContextWrapper
function OneLineBoard:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local props = self.props
    local points = props.points or {}
    local connections = props.connections or {}
    local path = props.path or {}
    local solved = props.solved == true
    if #points == 0 then
        return
    end

    local pad = 22
    local minX, minY, maxX, maxY = points[1].x, points[1].y, points[1].x, points[1].y
    for i = 2, #points do
        local p = points[i]
        if p.x < minX then minX = p.x end
        if p.y < minY then minY = p.y end
        if p.x > maxX then maxX = p.x end
        if p.y > maxY then maxY = p.y end
    end
    local spanX = math.max(maxX - minX, 1)
    local spanY = math.max(maxY - minY, 1)
    local innerW = math.max(l.w - pad * 2, 1)
    local innerH = math.max(l.h - pad * 2, 1)
    local scale = math.min(innerW / spanX, innerH / spanY)
    local ox = l.x + (l.w - spanX * scale) * 0.5
    local oy = l.y + (l.h - spanY * scale) * 0.5

    local function mapPoint(p)
        return ox + (p.x - minX) * scale, oy + (p.y - minY) * scale
    end

    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, l.x, l.y, l.w, l.h, 8)
    nvgFillColor(nvg, nvgRGBA(15, 23, 42, 255))
    nvgFill(nvg)
    nvgStrokeColor(nvg, nvgRGBA(51, 65, 85, 255))
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)

    nvgLineCap(nvg, NVG_ROUND)
    nvgStrokeWidth(nvg, 4)
    nvgStrokeColor(nvg, nvgRGBA(30, 41, 59, 255))
    for _, c in ipairs(connections) do
        local a, b = points[c[1] + 1], points[c[2] + 1]
        if a and b then
            local x1, y1 = mapPoint(a)
            local x2, y2 = mapPoint(b)
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, x1, y1)
            nvgLineTo(nvg, x2, y2)
            nvgStroke(nvg)
        end
    end

    local pathColor = solved and nvgRGBA(74, 222, 128, 255) or nvgRGBA(251, 191, 36, 255)
    nvgStrokeWidth(nvg, 3)
    nvgStrokeColor(nvg, pathColor)
    for i = 2, #path do
        local a, b = points[path[i - 1] + 1], points[path[i] + 1]
        if a and b then
            local x1, y1 = mapPoint(a)
            local x2, y2 = mapPoint(b)
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, x1, y1)
            nvgLineTo(nvg, x2, y2)
            nvgStroke(nvg)
        end
    end

    local lastIdx = path[#path]
    for i, p in ipairs(points) do
        local idx = i - 1
        local cx, cy = mapPoint(p)
        local inPath = false
        for _, n in ipairs(path) do
            if n == idx then
                inPath = true
                break
            end
        end
        local fill
        if lastIdx == idx then
            fill = nvgRGBA(245, 158, 11, 255)
        elseif inPath then
            fill = nvgRGBA(251, 191, 36, 255)
        else
            fill = nvgRGBA(51, 65, 85, 255)
        end
        nvgBeginPath(nvg)
        nvgCircle(nvg, cx, cy, 7)
        nvgFillColor(nvg, fill)
        nvgFill(nvg)
        if lastIdx == idx then
            nvgBeginPath(nvg)
            nvgCircle(nvg, cx, cy, 11)
            nvgStrokeColor(nvg, nvgRGBA(245, 158, 11, 255))
            nvgStrokeWidth(nvg, 1.5)
            nvgStroke(nvg)
        end
    end
end

function OneLineBoard:OnPointerDown(event)
    if oneLineSolved_ then
        return
    end
    local points = self.props.points or {}
    local connections = self.props.connections or {}
    if #points == 0 then
        return
    end
    local l = self:GetAbsoluteLayout()
    local pad = 22
    local minX, minY, maxX, maxY = points[1].x, points[1].y, points[1].x, points[1].y
    for i = 2, #points do
        local p = points[i]
        if p.x < minX then minX = p.x end
        if p.y < minY then minY = p.y end
        if p.x > maxX then maxX = p.x end
        if p.y > maxY then maxY = p.y end
    end
    local spanX = math.max(maxX - minX, 1)
    local spanY = math.max(maxY - minY, 1)
    local innerW = math.max(l.w - pad * 2, 1)
    local innerH = math.max(l.h - pad * 2, 1)
    local scale = math.min(innerW / spanX, innerH / spanY)
    local ox = l.x + (l.w - spanX * scale) * 0.5
    local oy = l.y + (l.h - spanY * scale) * 0.5

    local hitIdx = nil
    local bestDist = 22 * 22
    for i, p in ipairs(points) do
        local cx = ox + (p.x - minX) * scale
        local cy = oy + (p.y - minY) * scale
        local dx = event.x - cx
        local dy = event.y - cy
        local d2 = dx * dx + dy * dy
        if d2 <= bestDist then
            bestDist = d2
            hitIdx = i - 1
        end
    end
    if hitIdx == nil then
        return
    end

    if #oneLinePath_ == 0 then
        clearOneLinePath()
        oneLinePath_[1] = hitIdx
        Audio.PlaySound("click")
        if RefreshGameUI then RefreshGameUI() end
        return
    end

    local lastIdx = oneLinePath_[#oneLinePath_]
    if lastIdx == hitIdx then
        return
    end

    local edgeExists = false
    for _, c in ipairs(connections) do
        if (c[1] == lastIdx and c[2] == hitIdx) or (c[1] == hitIdx and c[2] == lastIdx) then
            edgeExists = true
            break
        end
    end
    if not edgeExists then
        Audio.PlaySound("error")
        return
    end
    if pathUsesEdge(oneLinePath_, lastIdx, hitIdx) then
        Audio.PlaySound("error")
        clearOneLinePath()
        if RefreshGameUI then RefreshGameUI() end
        return
    end

    oneLinePath_[#oneLinePath_ + 1] = hitIdx
    Audio.PlaySound("click")
    if checkOneLineVictory(oneLinePath_, connections) then
        oneLineSolved_ = true
        local answerParts = {}
        for i, n in ipairs(oneLinePath_) do
            answerParts[i] = tostring(n)
        end
        local success = GameEngine.HandlePuzzleSubmit(puzzleId_, interactableId_, table.concat(answerParts, ","))
        if success then
            UI_Puzzle.Close()
            return
        end
        oneLineSolved_ = false
        clearOneLinePath()
    end
    if RefreshGameUI then RefreshGameUI() end
end

function OneLineBoard:OnClick(event)
    -- 吞掉点击，避免冒泡关闭谜题面板
end

local function CreateOneLinePuzzle(puzzle)
    return UI.Panel {
        width = "100%",
        gap = 10,
        alignItems = "center",
        children = {
            OneLineBoard {
                width = 280,
                height = 280,
                points = puzzle.points or {},
                connections = puzzle.connections or {},
                path = oneLinePath_,
                solved = oneLineSolved_,
            },
            UI.Button {
                text = "重置路线",
                variant = "secondary",
                width = "100%",
                fontSize = 13,
                onClick = function(self)
                    clearOneLinePath()
                    Audio.PlaySound("click")
                    if RefreshGameUI then RefreshGameUI() end
                end,
            },
            UI.Label {
                text = "点击圆点连线。不能走重复路，必须走过所有预设路径。一旦走错，路线将重置。",
                fontSize = 11,
                fontColor = { 148, 163, 184, 220 },
                width = "100%",
                textAlign = "center",
                whiteSpace = "normal",
                wordBreak = "break-word",
                lineHeight = 1.4,
            },
        }
    }
end

---@class ImageGridBoard : Widget
local ImageGridBoard = Widget:Extend("ImageGridBoard")

---@param props table
function ImageGridBoard:Init(props)
    props = props or {}
    props.width = props.width or 280
    props.height = props.height or 280
    props.flexShrink = 0
    Widget.Init(self, props)
end

---@param nvg NVGContextWrapper
function ImageGridBoard:Render(nvg)
    local l = self:GetAbsoluteLayout()
    local gridSize = self.props.gridSize or 3
    local imgPath = self.props.imagePath or ""
    local tiles = self.props.tiles or imageGridTiles_
    local selected = self.props.selected
    local count = gridSize * gridSize
    if count <= 0 then
        return
    end

    nvgBeginPath(nvg)
    nvgRect(nvg, l.x, l.y, l.w, l.h)
    nvgFillColor(nvg, nvgRGBA(30, 41, 59, 255))
    nvgFill(nvg)

    if imgPath ~= "" and (imageGridImg_ < 0 or imageGridImgPath_ ~= imgPath) then
        imageGridImg_ = nvgCreateImage(nvg, imgPath, 0)
        imageGridImgPath_ = imgPath
    end

    local gap = 2
    local cellW = (l.w - gap * (gridSize + 1)) / gridSize
    local cellH = (l.h - gap * (gridSize + 1)) / gridSize

    for slot = 1, count do
        local r = math.floor((slot - 1) / gridSize)
        local c = (slot - 1) % gridSize
        local x = l.x + gap + c * (cellW + gap)
        local y = l.y + gap + r * (cellH + gap)
        local tileValue = tiles[slot] or (slot - 1)
        local srcRow = math.floor(tileValue / gridSize)
        local srcCol = tileValue % gridSize

        nvgSave(nvg)
        nvgScissor(nvg, x, y, cellW, cellH)
        if imageGridImg_ and imageGridImg_ >= 0 then
            local ox = x - srcCol * cellW
            local oy = y - srcRow * cellH
            local paint = nvgImagePattern(nvg, ox, oy, cellW * gridSize, cellH * gridSize, 0, imageGridImg_, 1)
            nvgBeginPath(nvg)
            nvgRect(nvg, x, y, cellW, cellH)
            nvgFillPaint(nvg, paint)
            nvgFill(nvg)
        else
            nvgBeginPath(nvg)
            nvgRect(nvg, x, y, cellW, cellH)
            nvgFillColor(nvg, nvgRGBA(51, 65, 85, 255))
            nvgFill(nvg)
        end
        nvgRestore(nvg)

        if selected == slot then
            nvgBeginPath(nvg)
            nvgRect(nvg, x, y, cellW, cellH)
            nvgStrokeColor(nvg, nvgRGBA(251, 191, 36, 255))
            nvgStrokeWidth(nvg, 2)
            nvgStroke(nvg)
        end
    end
end

function ImageGridBoard:OnPointerDown(event)
    if imageGridSolved_ then
        return
    end
    local l = self:GetAbsoluteLayout()
    local gridSize = self.props.gridSize or 3
    local gap = 2
    local cellW = (l.w - gap * (gridSize + 1)) / gridSize
    local cellH = (l.h - gap * (gridSize + 1)) / gridSize
    local lx = event.x - l.x - gap
    local ly = event.y - l.y - gap
    if lx < 0 or ly < 0 then
        return
    end
    local col = math.floor(lx / (cellW + gap))
    local row = math.floor(ly / (cellH + gap))
    if col < 0 or col >= gridSize or row < 0 or row >= gridSize then
        return
    end
    local slot = row * gridSize + col + 1
    if imageGridSelected_ == nil then
        imageGridSelected_ = slot
        Audio.PlaySound("click")
        if RefreshGameUI then RefreshGameUI() end
        return
    end
    if imageGridSelected_ == slot then
        imageGridSelected_ = nil
        if RefreshGameUI then RefreshGameUI() end
        return
    end
    local a = imageGridSelected_
    imageGridTiles_[a], imageGridTiles_[slot] = imageGridTiles_[slot], imageGridTiles_[a]
    imageGridSelected_ = nil
    Audio.PlaySound("pickup")
    local solved = true
    for i = 1, gridSize * gridSize do
        if imageGridTiles_[i] ~= (i - 1) then
            solved = false
            break
        end
    end
    if solved then
        imageGridSolved_ = true
        local puzzle = UI_Puzzle.GetCurrentPuzzle()
        local answer = (puzzle and puzzle.answer) or "solved"
        local success = GameEngine.HandlePuzzleSubmit(puzzleId_, interactableId_, answer)
        if success then
            UI_Puzzle.Close()
            return
        end
        imageGridSolved_ = false
    end
    if RefreshGameUI then RefreshGameUI() end
end

function ImageGridBoard:OnClick(event)
end

local function CreateImageGridPuzzle(puzzle)
    local gridSize = puzzle.gridSize or 3
    if GameState.GetDifficulty() == "STANDARD" then
        gridSize = gridSize + 1
    end
    if #imageGridTiles_ == 0 then
        initImageGrid(gridSize)
    end
    return UI.Panel {
        width = "100%",
        gap = 10,
        alignItems = "center",
        children = {
            ImageGridBoard {
                width = 280,
                height = 280,
                gridSize = gridSize,
                imagePath = resolvePuzzleImage(puzzle),
                tiles = imageGridTiles_,
                selected = imageGridSelected_,
            },
            UI.Label {
                text = imageGridSolved_ and "拼图完成" or "点击两个图块进行交换",
                fontSize = 12,
                fontColor = imageGridSolved_ and { 74, 222, 128, 255 } or { 148, 163, 184, 220 },
                textAlign = "center",
            },
        }
    }
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
        inputWidget = CreateImageGridPuzzle(puzzle)
    elseif puzzle.type == "one_line" then
        inputWidget = CreateOneLinePuzzle(puzzle)
    else
        -- text 或其他类型
        inputWidget = CreateTextInput()
    end

    local isOneLine = puzzle.type == "one_line"
    local isVisualPuzzle = isOneLine or puzzle.type == "image_grid"
    local titleText = "输入密码"
    if puzzle.type == "image_grid" then
        titleText = "还原拼图"
    elseif isOneLine then
        titleText = "一笔画连线"
    elseif puzzle.type == "symbol" then
        titleText = "输入符号"
    end

    ---@type table[]
    local bodyChildren = {}
    bodyChildren[1] = UI.Label {
        text = titleText,
        fontSize = 16,
        fontColor = { 245, 158, 11, 255 },
        width = "100%",
        textAlign = "center",
    }
    bodyChildren[2] = UI.Label {
        text = puzzle.description or "解开谜题",
        fontSize = 13,
        fontColor = { 200, 200, 220, 255 },
        width = "100%",
        textAlign = "center",
        whiteSpace = "normal",
        wordBreak = "break-word",
        lineHeight = 1.4,
    }

    if not isVisualPuzzle then
        bodyChildren[#bodyChildren + 1] = UI.Panel {
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
        }
    end

    bodyChildren[#bodyChildren + 1] = inputWidget
    bodyChildren[#bodyChildren + 1] = UI.Panel {
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
    }

    if not isVisualPuzzle then
        bodyChildren[#bodyChildren + 1] = UI.Button {
            text = "确认",
            variant = "primary",
            width = "80%",
            onClick = function(self)
                handleSubmit()
            end,
        }
        bodyChildren[#bodyChildren + 1] = UI.Button {
            text = "返回",
            variant = "ghost",
            fontSize = 13,
            onClick = function(self)
                UI_Puzzle.Close()
            end,
        }
    else
        bodyChildren[#bodyChildren + 1] = UI.Button {
            text = "关闭 / 放弃",
            variant = "ghost",
            width = "100%",
            fontSize = 13,
            onClick = function(self)
                UI_Puzzle.Close()
            end,
        }
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
                        children = bodyChildren,
                    },
                }
            }
        }
    }
end

return UI_Puzzle
