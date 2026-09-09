-- ============================================================================
-- Audio.lua - 音频系统 (BGM + SFX + Morse Code)
-- 对应 H5: BGM 播放、交互音效、Morse 音频提示
-- ============================================================================

local Audio = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

local gameData_ = nil
local bgmNode_ = nil         -- BGM 音源节点
local sfxNode_ = nil         -- SFX 音源节点
local morseNode_ = nil       -- Morse 音源节点
local bgmSource_ = nil       -- BGM SoundSource
local bgmPlaying_ = false

-- ============================================================================
-- 初始化
-- ============================================================================

function Audio.Init(gameData)
    gameData_ = gameData
    print("[Audio] Init")
end

--- 设置音频场景节点（在 Start 后调用）
function Audio.SetupNodes()
    -- 创建 BGM 音频节点
    if not bgmNode_ then
        bgmNode_ = Node()
        bgmSource_ = bgmNode_:CreateComponent("SoundSource")
        bgmSource_.soundType = "Music"
        bgmSource_.gain = 0.4
    end
    -- 创建 SFX 音频节点
    if not sfxNode_ then
        sfxNode_ = Node()
    end
    -- 创建 Morse 音频节点
    if not morseNode_ then
        morseNode_ = Node()
    end
end

-- ============================================================================
-- BGM
-- ============================================================================

--- 播放背景音乐
function Audio.PlayBGM()
    Audio.SetupNodes()

    -- 查找可用的 BGM 文件
    local bgmPath = nil
    local Data = require("Data")
    if gameData_ and gameData_.meta then
        local rawBgm = gameData_.meta.bgmUrl or gameData_.meta.musicUrl
        if rawBgm and rawBgm ~= "" then
            bgmPath = Data.ResolveAssetPath(rawBgm)
        end
    end

    -- 未指定或文件缺失时，回退到当前游戏目录下的默认 BGM
    if (not bgmPath or bgmPath == "" or not cache:Exists(bgmPath)) and Data.currentGameBaseDir ~= "" then
        local fallbacks = {
            Data.currentGameBaseDir .. "bgm.mp3",
            Data.currentGameBaseDir .. "bgm.ogg",
            Data.currentGameBaseDir .. "bgm.wav",
        }
        for _, candidate in ipairs(fallbacks) do
            if cache:Exists(candidate) then
                bgmPath = candidate
                break
            end
        end
    end

    -- 如果没有指定 BGM，使用默认音频文件
    if not bgmPath or bgmPath == "" then
        -- 尝试加载 assets/audio/ 中的音乐文件
        if cache:Exists("audio/music_1779892785649.ogg") then
            bgmPath = "audio/music_1779892785649.ogg"
        end
    end

    if not bgmPath or bgmPath == "" then
        print("[Audio] No BGM file found")
        return
    end

    local sound = cache:GetResource("Sound", bgmPath)
    if not sound then
        print("[Audio] BGM resource not found: " .. bgmPath)
        return
    end

    sound.looped = true
    bgmSource_:Play(sound)
    bgmPlaying_ = true
    print("[Audio] BGM playing: " .. bgmPath)
end

--- 停止背景音乐
function Audio.StopBGM()
    if bgmSource_ then
        bgmSource_:Stop()
    end
    bgmPlaying_ = false
end

-- ============================================================================
-- 音效 (SFX)
-- ============================================================================

--- 播放命名音效
---@param name string 音效名: "click" | "success" | "error" | "pickup" | "transition" | "examine" | "open"
function Audio.PlaySound(name)
    -- 使用引擎内置 beep 音效模拟（游戏无自定义 SFX 文件）
    -- 后续可替换为实际音效文件
    print("[Audio] SFX: " .. name)
end

-- ============================================================================
-- Morse Code 播放
-- ============================================================================

--- 播放 Morse 编码音频（简化实现：仅打印提示）
---@param message string 原始消息内容
function Audio.PlayMorseCode(message)
    if not message or #message == 0 then return end
    print("[Audio] Morse: " .. message)
    -- 注：完整实现需要程序化生成 Morse 声音
    -- 当前简化为日志输出，后续可用引擎内置音频合成
end

-- ============================================================================
-- 清理
-- ============================================================================

function Audio.Shutdown()
    Audio.StopBGM()
    if bgmNode_ then bgmNode_:Dispose() bgmNode_ = nil end
    if sfxNode_ then sfxNode_:Dispose() sfxNode_ = nil end
    if morseNode_ then morseNode_:Dispose() morseNode_ = nil end
    bgmSource_ = nil
    print("[Audio] Shutdown")
end

return Audio
