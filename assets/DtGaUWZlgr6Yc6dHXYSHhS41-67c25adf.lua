-- ============================================================================
-- GameEngine.lua - 游戏交互引擎核心
-- 对应 H5: useGameEngine.ts 中的 handleInteract/handleMove/handleExplore/handlePuzzleSubmit
-- ============================================================================

local GameState = require("GameState")
local UI_Message = require("UI_Message")
local Audio = require("Audio")

---@type fun()
RefreshGameUI = RefreshGameUI

local GameEngine = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

local gameData_ = nil
local selectedItemId_ = nil      -- 当前选中的物品ID (用于解锁)
local isExploring_ = false       -- 是否正在探索中
local exploreTimer_ = 0          -- 探索计时器
local pendingVictory_ = false    -- 延迟胜利标记
local pendingVictoryTimer_ = 0   -- 胜利延迟计时器
local pendingPuzzle_ = nil       -- 延迟打开的谜题 {puzzleId, interactableId}

local EXPLORE_INTERVAL = 1.5     -- 探索间隔(秒)
local VICTORY_DELAY = 3.0        -- 胜利延迟(秒)

-- ============================================================================
-- 初始化
-- ============================================================================

function GameEngine.Init(gameData)
    gameData_ = gameData
end

function GameEngine.Reset()
    selectedItemId_ = nil
    isExploring_ = false
    exploreTimer_ = 0
    pendingVictory_ = false
    pendingVictoryTimer_ = 0
    pendingPuzzle_ = nil
end

-- ============================================================================
-- 物品选择
-- ============================================================================

function GameEngine.GetSelectedItemId()
    return selectedItemId_
end

function GameEngine.SetSelectedItem(itemId)
    if selectedItemId_ == itemId then
        selectedItemId_ = nil  -- 取消选择
    else
        selectedItemId_ = itemId
    end
    print("[Engine] Selected item: " .. tostring(selectedItemId_))
end

function GameEngine.ClearSelectedItem()
    selectedItemId_ = nil
end

-- ============================================================================
-- 交互完成判断 (对应 H5: isInteractableCompleted)
-- ============================================================================

--- 判断一个交互物是否已完成
---@param inter table Interactable
---@param sceneId string|nil 所属场景；缺省为当前场景
---@return boolean
function GameEngine.IsInteractableCompleted(inter, sceneId)
    if not inter then return false end
    local activeId = sceneId or GameState.ResolveActiveSceneId()

    -- 1. 谜题类: 检查谜题的 rewardFlag
    if (inter.isPuzzle or inter.puzzleId) and inter.puzzleId then
        local puzzle = gameData_.puzzles[inter.puzzleId]
        if puzzle then
            return GameState.GetFlag(puzzle.rewardFlag) == true
        end
    end

    -- 2. 线索提供者: 关联谜题解开前不视为完成（可反复查看线索）
    -- 谜题解开后，若仍需插入物品且尚未解锁，也不算完成（如 VCR 还没插带）
    if inter.clueForPuzzleId then
        local puzzle = gameData_.puzzles and gameData_.puzzles[inter.clueForPuzzleId]
        if puzzle then
            if GameState.GetFlag(puzzle.rewardFlag) ~= true then
                return false
            end
            if inter.requiredItemId then
                local implicitUnlockFlag = "unlocked_" .. activeId .. "_" .. inter.id
                local unlocked = (inter.flagReward and GameState.GetFlag(inter.flagReward))
                    or GameState.GetFlag(implicitUnlockFlag)
                if not unlocked then
                    return false
                end
            end
            return true
        end
    end

    -- 3. 通用检查
    local isDoneByFlag = inter.hiddenIfFlag and GameState.GetFlag(inter.hiddenIfFlag)
    local isDoneByItem = inter.itemRewardId and GameState.GetFlag("found_" .. inter.itemRewardId)
    local isDoneByFlagReward = inter.flagReward and GameState.GetFlag(inter.flagReward)
    local isExplicitlyDone = GameState.GetFlag("interacted_" .. activeId .. "_" .. inter.id)

    return (isDoneByFlag or isDoneByItem or isDoneByFlagReward or isExplicitlyDone) and true or false
end

-- ============================================================================
-- 场景移动 (对应 H5: handleMove)
-- ============================================================================

--- 移动到目标场景
---@param targetSceneId string
---@param requiredFlag string|nil
---@param locked boolean|nil
function GameEngine.HandleMove(targetSceneId, requiredFlag, locked)
    -- 停止探索
    if isExploring_ then
        isExploring_ = false
    end

    -- 消息播放中则推进
    if UI_Message.IsPlaying() then
        UI_Message.Advance()
        return
    end

    -- 检查是否解锁
    local isUnlockedByFlag = requiredFlag and GameState.GetFlag(requiredFlag)
    if (locked and not isUnlockedByFlag) or (requiredFlag and not GameState.GetFlag(requiredFlag)) then
        local msg = (locked and not isUnlockedByFlag) and "路被堵住了。" or "你还不能去那边。"
        UI_Message.QueueMessages({ msg })
        Audio.PlaySound("error")
        return
    end

    -- 执行移动
    Audio.PlaySound("transition")
    GameState.SetCurrentScene(targetSceneId)

    -- 显示新场景描述
    local scene = gameData_.scenes[targetSceneId]
    if scene and scene.description and #scene.description > 0 then
        UI_Message.QueueMessages({ scene.description })
    end

    -- 刷新 UI
    RefreshGameUI()
    print("[Engine] Moved to: " .. targetSceneId)
end

-- ============================================================================
-- 交互处理 (对应 H5: handleInteract - 核心逻辑)
-- ============================================================================

--- 处理交互
---@param target table Interactable
function GameEngine.HandleInteract(target)
    if not target then return end
    local activeId = GameState.ResolveActiveSceneId()

    -- 停止探索
    if isExploring_ then
        isExploring_ = false
    end

    -- 消息播放中则推进
    if UI_Message.IsPlaying() then
        UI_Message.Advance()
        return
    end

    -- 检查 requiredFlag（优先用关卡 lockedMessage，避免误以为密码无效）
    if target.requiredFlag and not GameState.GetFlag(target.requiredFlag) then
        UI_Message.QueueMessages({ target.lockedMessage or "你现在还不能那样做。" })
        Audio.PlaySound("error")
        return
    end

    -- 检查是否已解锁
    local implicitUnlockFlag = "unlocked_" .. activeId .. "_" .. target.id
    local isExplicitlyUnlocked = target.flagReward and GameState.GetFlag(target.flagReward)
    local isAlreadyUnlocked = isExplicitlyUnlocked or GameState.GetFlag(implicitUnlockFlag)

    -- 需要物品但未选中正确物品
    if target.requiredItemId and not isAlreadyUnlocked and selectedItemId_ ~= target.requiredItemId then
        local msg = target.lockedMessage or "它锁住了。"
        UI_Message.QueueMessages({ msg })
        Audio.PlaySound("error")
        return
    end

    -- --- 音频逻辑 (Morse Code) ---
    local audioHint = ""
    local audioFlagsUpdate = {}
    if target.audioMessage then
        Audio.PlayMorseCode(target.audioMessage)
        local countKey = "listen_count_" .. target.id
        local currentCount = (GameState.GetFlag(countKey) or 0)
        if type(currentCount) ~= "number" then currentCount = 0 end
        local newCount = currentCount + 1
        audioFlagsUpdate[countKey] = newCount

        if GameState.GetDifficulty() == "EASY" and newCount >= 3 then
            audioHint = "(你仔细辨认，记录下了这段音频的答案是: " .. target.audioMessage .. ")"
        elseif newCount >= 5 then
            local morse = GameEngine.TextToMorse(target.audioMessage)
            audioHint = "(你仔细辨认，记录下了信号的节奏：" .. morse .. ")"
        end
    end

    -- --- 已完成检查 ---
    local isCompleted = GameEngine.IsInteractableCompleted(target)
    if isCompleted then
        local isStandardAudio = GameState.GetDifficulty() == "STANDARD" and target.audioMessage
        if not isStandardAudio then
            if target.postInteractionMessage then
                UI_Message.QueueMessages({ target.postInteractionMessage })
                Audio.PlaySound("examine")
            elseif target.clueForPuzzleId and not target.itemRewardId then
                if target.dialogue and #target.dialogue > 0 then
                    UI_Message.QueueMessages(target.dialogue)
                else
                    UI_Message.QueueMessages({ target.description })
                end
                Audio.PlaySound("examine")
            else
                UI_Message.QueueMessages({ "这里没什么了。" })
            end
        end
        -- 更新音频计数
        if next(audioFlagsUpdate) then
            GameState.SetFlags(audioFlagsUpdate)
        end
        if #audioHint > 0 then
            UI_Message.QueueMessages({ audioHint })
        end
        return
    end

    local logsToAdd = {}
    local interactionFlag = "interacted_" .. activeId .. "_" .. target.id

    -- --- 物品解锁成功 ---
    if target.requiredItemId and not isAlreadyUnlocked and selectedItemId_ == target.requiredItemId then
        local item = gameData_.items[selectedItemId_]
        local unlockMsg = target.lockedMessage and ("使用了 " .. (item and item.name or "物品") .. "。") or "起作用了。"
        logsToAdd[#logsToAdd + 1] = unlockMsg
        Audio.PlaySound("success")

        local newFlags = {}
        for k, v in pairs(audioFlagsUpdate) do newFlags[k] = v end
        newFlags[implicitUnlockFlag] = true
        newFlags[interactionFlag] = true

        -- 判断是否消耗物品
        local shouldConsume = true
        if item and (item.type == "CLUE" or item.type == "NOTE" or item.clueForPuzzleId) then
            shouldConsume = false
        else
            -- 检查其他交互物是否也需要此物品
            for _, scene in pairs(gameData_.scenes) do
                for _, inter in ipairs(scene.interactables or {}) do
                    if not (scene.id == activeId and inter.id == target.id) then
                        if inter.requiredItemId == selectedItemId_ then
                            if not GameEngine.IsInteractableCompleted(inter, scene.id) then
                                shouldConsume = false
                                break
                            end
                        end
                    end
                end
                if not shouldConsume then break end
            end
        end

        if shouldConsume then
            GameState.RemoveItem(selectedItemId_)
        end

        -- 非谜题类交互的后续处理
        if not target.isPuzzle then
            if target.flagReward then newFlags[target.flagReward] = true end
            if target.postInteractionMessage then
                newFlags["interacted_" .. activeId .. "_" .. target.id] = true
                logsToAdd[#logsToAdd + 1] = target.postInteractionMessage
            end
            if target.itemRewardId and gameData_.items[target.itemRewardId] then
                if not GameState.HasItem(target.itemRewardId) then
                    GameState.AddItem(target.itemRewardId)
                    if target.hiddenIfFlag then newFlags[target.hiddenIfFlag] = true end
                    logsToAdd[#logsToAdd + 1] = "获得了：" .. gameData_.items[target.itemRewardId].name
                    Audio.PlaySound("pickup")
                end
            end
            if target.winsGame then
                if gameData_.meta.endingSceneId then
                    GameState.SetCurrentScene(gameData_.meta.endingSceneId)
                end
                pendingVictory_ = true
                pendingVictoryTimer_ = 0
            end
        end

        if target.dialogue and not target.isPuzzle then
            for _, d in ipairs(target.dialogue) do
                logsToAdd[#logsToAdd + 1] = d
            end
        end
        if #audioHint > 0 then logsToAdd[#logsToAdd + 1] = audioHint end

        GameState.SetFlags(newFlags)
        selectedItemId_ = nil
        if #logsToAdd > 0 then UI_Message.QueueMessages(logsToAdd) end

        -- 如果是谜题，继续触发
        if target.isPuzzle then
            -- fall through to puzzle trigger below
        else
            RefreshGameUI()
            return
        end
    end

    -- --- 谜题触发 ---
    if target.isPuzzle and target.puzzleId and gameData_.puzzles[target.puzzleId] then
        local puzzle = gameData_.puzzles[target.puzzleId]
        if not GameState.GetFlag(puzzle.rewardFlag) then
            if next(audioFlagsUpdate) then GameState.SetFlags(audioFlagsUpdate) end
            local hasText = (target.dialogue and #target.dialogue > 0) or (#target.description > 0)
            if hasText then
                if target.dialogue and #target.dialogue > 0 then
                    UI_Message.QueueMessages(target.dialogue)
                else
                    UI_Message.QueueMessages({ target.description })
                end
                if #audioHint > 0 then UI_Message.QueueMessages({ audioHint }) end
                -- 消息播完后再打开谜题
                pendingPuzzle_ = { puzzleId = target.puzzleId, interactableId = target.id }
            else
                if #audioHint > 0 then UI_Message.QueueMessages({ audioHint }) end
                Audio.PlaySound("open")
                GameEngine.OpenPuzzle(target.puzzleId, target.id)
            end
            return
        end
    end

    -- --- 通用交互 ---
    local interactionHappened = false
    local hasInteracted = GameState.GetFlag(interactionFlag)

    if (isAlreadyUnlocked or hasInteracted) and target.postInteractionMessage then
        logsToAdd[#logsToAdd + 1] = target.postInteractionMessage
        interactionHappened = true
    elseif target.dialogue and #target.dialogue > 0 then
        for _, d in ipairs(target.dialogue) do
            logsToAdd[#logsToAdd + 1] = d
        end
        interactionHappened = true
    elseif not target.itemRewardId then
        logsToAdd[#logsToAdd + 1] = target.description
        interactionHappened = true
    end

    if #audioHint > 0 then logsToAdd[#logsToAdd + 1] = audioHint end

    local newFlags = {}
    for k, v in pairs(audioFlagsUpdate) do newFlags[k] = v end
    local stateChanged = next(audioFlagsUpdate) ~= nil

    if not GameState.GetFlag(interactionFlag) then
        newFlags[interactionFlag] = true
        stateChanged = true
    end
    if target.postInteractionMessage then
        newFlags["interacted_" .. activeId .. "_" .. target.id] = true
        stateChanged = true
    end
    if target.clueForPuzzleId then
        local flagKey = "interacted_" .. activeId .. "_" .. target.id
        if not GameState.GetFlag(flagKey) then
            newFlags[flagKey] = true
            stateChanged = true
        end
    end
    if target.itemRewardId and gameData_.items[target.itemRewardId] then
        if not GameState.GetFlag("found_" .. target.itemRewardId) then
            GameState.AddItem(target.itemRewardId)
            if target.hiddenIfFlag then newFlags[target.hiddenIfFlag] = true end
            logsToAdd[#logsToAdd + 1] = "获得了：" .. gameData_.items[target.itemRewardId].name
            Audio.PlaySound("pickup")
            stateChanged = true
        end
    end
    if target.flagReward and not GameState.GetFlag(target.flagReward) then
        newFlags[target.flagReward] = true
        stateChanged = true
    end

    if stateChanged then GameState.SetFlags(newFlags) end
    if not interactionHappened and not target.itemRewardId then Audio.PlaySound("examine") end
    if #logsToAdd > 0 then UI_Message.QueueMessages(logsToAdd) end

    -- 移动到目标场景
    if target.targetSceneId then
        GameEngine.HandleMove(target.targetSceneId)
    end

    -- 胜利检查
    if target.winsGame then
        if gameData_.meta.endingSceneId then
            GameState.SetCurrentScene(gameData_.meta.endingSceneId)
        end
        pendingVictory_ = true
        pendingVictoryTimer_ = 0
    end

    RefreshGameUI()
end

-- ============================================================================
-- 谜题处理 (对应 H5: handlePuzzleSubmit)
-- ============================================================================

--- 打开谜题面板
function GameEngine.OpenPuzzle(puzzleId, interactableId)
    local UI_Puzzle = require("UI_Puzzle")
    UI_Puzzle.Open(puzzleId, interactableId)
end

--- 提交谜题答案
---@param puzzleId string
---@param interactableId string
---@param inputAnswer string
---@return boolean 是否正确
function GameEngine.HandlePuzzleSubmit(puzzleId, interactableId, inputAnswer)
    if not puzzleId or not gameData_.puzzles[puzzleId] then return false end
    local puzzle = gameData_.puzzles[puzzleId]
    local activeId = GameState.ResolveActiveSceneId()

    local finalInput = (inputAnswer or ""):match("^%s*(.-)%s*$") or ""
    local cleanAnswer = (puzzle.answer or ""):match("^%s*(.-)%s*$") or ""

    -- 一笔画：H5 通关后把路径 join 提交；answer 为 auto 时走完全部边即正确
    if puzzle.type == "one_line" then
        local connections = puzzle.connections or {}
        if #connections == 0 then
            UI_Message.QueueMessages({ "错误：解答不正确。" })
            Audio.PlaySound("error")
            return false, "错误：解答不正确。"
        end
        local remaining = {}
        local remainingCount = 0
        for _, c in ipairs(connections) do
            remainingCount = remainingCount + 1
            remaining[remainingCount] = { math.min(c[1], c[2]), math.max(c[1], c[2]) }
        end
        local nodes = {}
        for token in (finalInput .. ","):gmatch("([^,]*),") do
            local n = tonumber((token:match("^%s*(.-)%s*$")))
            if n ~= nil then
                nodes[#nodes + 1] = n
            end
        end
        local okPath = #nodes >= 2
        if okPath then
            for i = 1, #nodes - 1 do
                local a, b = nodes[i], nodes[i + 1]
                local lo, hi = math.min(a, b), math.max(a, b)
                local found = false
                for j = 1, remainingCount do
                    local e = remaining[j]
                    if e and e[1] == lo and e[2] == hi then
                        remaining[j] = remaining[remainingCount]
                        remaining[remainingCount] = nil
                        remainingCount = remainingCount - 1
                        found = true
                        break
                    end
                end
                if not found then
                    okPath = false
                    break
                end
            end
            if okPath and remainingCount ~= 0 then
                okPath = false
            end
        end
        if not okPath then
            UI_Message.QueueMessages({ "错误：解答不正确。" })
            Audio.PlaySound("error")
            return false, "错误：解答不正确。"
        end
        -- 对应 H5：走完全部边即通关，再提交预设 answer
        finalInput = cleanAnswer
    end

    -- 根据类型清洗输入
    if puzzle.type == "numeric" then
        finalInput = finalInput:gsub("%D", "")
        cleanAnswer = cleanAnswer:gsub("%D", "")
    elseif puzzle.type == "symbol" and puzzle.choices and #puzzle.choices > 0 then
        local choiceSet = {}
        for _, c in ipairs(puzzle.choices) do choiceSet[c] = true end
        -- UTF-8 感知的字符遍历
        local UTF8_PATTERN = "[%z\1-\127\194-\244][\128-\191]*"
        local filtered = {}
        for char in finalInput:gmatch(UTF8_PATTERN) do
            if choiceSet[char] then filtered[#filtered + 1] = char end
        end
        finalInput = table.concat(filtered)
        local filteredAnswer = {}
        for char in cleanAnswer:gmatch(UTF8_PATTERN) do
            if choiceSet[char] then filteredAnswer[#filteredAnswer + 1] = char end
        end
        cleanAnswer = table.concat(filteredAnswer)
    end

    if finalInput == cleanAnswer then
        -- 正确
        Audio.PlaySound("success")
        local newFlags = {}
        newFlags[puzzle.rewardFlag] = true
        local logs = { puzzle.rewardMessage or "解答正确。" }

        -- 查找关联的交互物
        local scene = gameData_.scenes[activeId]
        if scene then
            for _, inter in ipairs(scene.interactables or {}) do
                if inter.id == interactableId then
                    newFlags["interacted_" .. activeId .. "_" .. inter.id] = true
                    if inter.itemRewardId and gameData_.items[inter.itemRewardId] then
                        if not GameState.HasItem(inter.itemRewardId) then
                            GameState.AddItem(inter.itemRewardId)
                            if inter.hiddenIfFlag then newFlags[inter.hiddenIfFlag] = true end
                            logs[#logs + 1] = "获得了：" .. gameData_.items[inter.itemRewardId].name
                            Audio.PlaySound("pickup")
                        end
                    end
                    if inter.flagReward then newFlags[inter.flagReward] = true end
                    if inter.winsGame then
                        if gameData_.meta.endingSceneId then
                            GameState.SetCurrentScene(gameData_.meta.endingSceneId)
                        end
                        pendingVictory_ = true
                        pendingVictoryTimer_ = 0
                    end
                    break
                end
            end
        end

        -- 谜题解开后，同场景中依赖该 flag 的交互物自动揭示（如保险柜内的芯片）
        if puzzle.rewardFlag and scene then
            for _, inter in ipairs(scene.interactables or {}) do
                if inter.requiredFlag == puzzle.rewardFlag then
                    newFlags["revealed_" .. activeId .. "_" .. inter.id] = true
                end
            end
        end

        GameState.SetFlags(newFlags)
        UI_Message.QueueMessages(logs)
        RefreshGameUI()
        return true
    else
        -- 错误
        UI_Message.QueueMessages({ "错误：解答不正确。" })
        Audio.PlaySound("error")
        return false, "错误：解答不正确。"
    end
end

-- ============================================================================
-- 探索系统 (对应 H5: handleExplore + useEffect 循环)
-- ============================================================================

function GameEngine.IsExploring()
    return isExploring_
end

function GameEngine.ToggleExploration()
    isExploring_ = not isExploring_
    exploreTimer_ = 0
    if isExploring_ then
        print("[Engine] Exploration started")
    else
        print("[Engine] Exploration stopped")
    end
    RefreshGameUI()
end

function GameEngine.StopExploration()
    if isExploring_ then
        isExploring_ = false
        RefreshGameUI()
    end
end

--- 探索更新（每帧调用）
---@param dt number
function GameEngine.UpdateExploration(dt)
    -- 延迟胜利：对应 H5 仅在 msgQueue 清空后才启动 3 秒计时
    if pendingVictory_ then
        if UI_Message.IsPlaying() then
            pendingVictoryTimer_ = 0
        else
            pendingVictoryTimer_ = pendingVictoryTimer_ + dt
            if pendingVictoryTimer_ >= VICTORY_DELAY then
                pendingVictory_ = false
                GameState.SetGameWon()
            end
        end
    end

    -- 待打开谜题（消息播完后触发）
    if pendingPuzzle_ and not UI_Message.IsPlaying() then
        Audio.PlaySound("open")
        GameEngine.OpenPuzzle(pendingPuzzle_.puzzleId, pendingPuzzle_.interactableId)
        pendingPuzzle_ = nil
    end

    -- 探索逻辑
    if not isExploring_ then return end

    exploreTimer_ = exploreTimer_ + dt
    if exploreTimer_ < EXPLORE_INTERVAL then return end
    exploreTimer_ = 0

    local activeId = GameState.ResolveActiveSceneId()
    local scene = gameData_.scenes[activeId]
    if not scene then
        isExploring_ = false
        return
    end

    -- 查找候选交互物
    local candidates = {}
    for _, inter in ipairs(scene.interactables or {}) do
        local validCandidate = true
        if inter.hiddenIfFlag and GameState.GetFlag(inter.hiddenIfFlag) then
            validCandidate = false
        end
        if inter.requiredFlag and not GameState.GetFlag(inter.requiredFlag) then
            validCandidate = false
        end
        if GameState.GetFlag("revealed_" .. activeId .. "_" .. inter.id) then
            validCandidate = false
        end
        if validCandidate then
            candidates[#candidates + 1] = inter
        end
    end

    -- 没有更多候选，停止探索
    if #candidates == 0 then
        UI_Message.QueueMessages({ "这里似乎没有更多线索了。" })
        isExploring_ = false
        RefreshGameUI()
        return
    end

    -- 随机揭示一个
    local idx = math.random(1, #candidates)
    local foundItem = candidates[idx]
    GameState.SetFlag("revealed_" .. activeId .. "_" .. foundItem.id, true)
    Audio.PlaySound("success")
    RefreshGameUI()
end

-- ============================================================================
-- 可交互物状态查询 (对应 H5: getInteractablesWithStatus)
-- ============================================================================

--- 获取当前场景中可见的交互物列表（含状态）
---@return table[] {interactable, status, isRevealed}
function GameEngine.GetInteractablesWithStatus()
    local activeId = GameState.ResolveActiveSceneId()
    local scene = gameData_.scenes[activeId]
    if not scene then return {} end

    local result = {}
    for _, inter in ipairs(scene.interactables or {}) do
        local status = "active"
        local isRevealed = GameState.GetFlag("revealed_" .. activeId .. "_" .. inter.id) == true

        if inter.requiredFlag and not GameState.GetFlag(inter.requiredFlag) then
            status = "hidden"
        elseif GameEngine.IsInteractableCompleted(inter, activeId) then
            status = "exhausted"
        end

        if status ~= "hidden" then
            result[#result + 1] = {
                interactable = inter,
                status = status,
                isRevealed = isRevealed,
            }
        end
    end
    return result
end

-- ============================================================================
-- Morse Code 转换
-- ============================================================================

local MORSE_MAP = {
    A = ".-",   B = "-...", C = "-.-.", D = "-..",  E = ".",    F = "..-.",
    G = "--.",  H = "....", I = "..",   J = ".---", K = "-.-",  L = ".-..",
    M = "--",   N = "-.",   O = "---",  P = ".--.", Q = "--.-", R = ".-.",
    S = "...",  T = "-",    U = "..-",  V = "...-", W = ".--",  X = "-..-",
    Y = "-.--", Z = "--..",
    ["0"] = "-----", ["1"] = ".----", ["2"] = "..---", ["3"] = "...--", ["4"] = "....-",
    ["5"] = ".....", ["6"] = "-....", ["7"] = "--...", ["8"] = "---..", ["9"] = "----.",
    ["."] = ".-.-.-", [","] = "--..--", ["?"] = "..--..", ["!"] = "-.-.--",
}

---将文本转为 Morse 码字符串（各字符用空格分隔）
---@param text string
---@return string
function GameEngine.TextToMorse(text)
    local parts = {}
    for i = 1, #text do
        local ch = string.upper(string.sub(text, i, i))
        parts[#parts + 1] = MORSE_MAP[ch] or ch
    end
    return table.concat(parts, " ")
end

return GameEngine
