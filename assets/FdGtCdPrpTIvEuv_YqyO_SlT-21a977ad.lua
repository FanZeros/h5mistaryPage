-- ============================================================================
-- Ads.lua - 激励视频广告封装
-- 对应 H5: services/adService.ts
-- ============================================================================

---@type table|nil
sdk = sdk

local Ads = {}

local inFlight_ = false

--- 展示激励视频
---@param onSuccess fun()
---@param onFailure fun(msg: string)
function Ads.ShowReward(onSuccess, onFailure)
    if inFlight_ then
        print("[Ads] ignored: already in flight")
        return
    end

    inFlight_ = true
    local completed = false
    local callbackFired = false

    local function finish(result)
        if completed then
            return
        end
        completed = true
        inFlight_ = false

        if result and result.success == true then
            print("[Ads] reward granted")
            if onSuccess then
                onSuccess()
            end
            return
        end

        local msg = (result and result.msg) or "广告暂不可用，请稍后重试"
        print("[Ads] failed: " .. tostring(msg))
        if onFailure then
            onFailure(msg)
        end
    end

    if not sdk or not sdk.ShowRewardVideoAd then
        finish({ success = false, msg = "广告暂不可用，请稍后重试" })
        return
    end

    local accepted = sdk:ShowRewardVideoAd(function(result)
        callbackFired = true
        finish(result)
    end)

    if accepted == false and not callbackFired then
        finish({ success = false, msg = "广告暂不可用，请稍后重试" })
    end
end

function Ads.IsInFlight()
    return inFlight_
end

return Ads
