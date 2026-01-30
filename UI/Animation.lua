-- HonorLog Animation Utilities
-- Reusable animation system for smooth UI transitions

local ADDON_NAME, HonorLog = ...

--------------------------------------------------------------------------------
-- ANIMATION UTILITIES
--------------------------------------------------------------------------------
local activeAnimations = {}

-- Smooth easing function (ease-out quad)
local function EaseOutQuad(t)
    return t * (2 - t)
end

-- Smooth easing function (ease-in-out)
local function EaseInOutQuad(t)
    if t < 0.5 then
        return 2 * t * t
    else
        return 1 - (-2 * t + 2) ^ 2 / 2
    end
end

-- Animate a value from start to target over duration
local function AnimateValue(id, startVal, targetVal, duration, onUpdate, onComplete)
    -- Cancel any existing animation with same ID
    if activeAnimations[id] then
        activeAnimations[id].cancelled = true
    end

    local animation = {
        startVal = startVal,
        targetVal = targetVal,
        duration = duration,
        elapsed = 0,
        onUpdate = onUpdate,
        onComplete = onComplete,
        cancelled = false,
    }

    activeAnimations[id] = animation

    -- Parent to UIParent to ensure OnUpdate events are received in TBC Classic
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetScript("OnUpdate", function(self, elapsed)
        if animation.cancelled then
            self:SetScript("OnUpdate", nil)
            activeAnimations[id] = nil
            return
        end

        animation.elapsed = animation.elapsed + elapsed
        local progress = math.min(animation.elapsed / animation.duration, 1)
        local easedProgress = EaseOutQuad(progress)
        local currentVal = animation.startVal + (animation.targetVal - animation.startVal) * easedProgress

        if animation.onUpdate then
            animation.onUpdate(currentVal, progress)
        end

        if progress >= 1 then
            self:SetScript("OnUpdate", nil)
            activeAnimations[id] = nil
            if animation.onComplete then
                animation.onComplete()
            end
        end
    end)

    return animation
end

-- Cancel an animation by ID
local function CancelAnimation(id)
    if activeAnimations[id] then
        activeAnimations[id].cancelled = true
        activeAnimations[id] = nil
    end
end

-- Cancel all active animations
local function CancelAllAnimations()
    for id, animation in pairs(activeAnimations) do
        animation.cancelled = true
    end
    wipe(activeAnimations)
end

--------------------------------------------------------------------------------
-- ANIMATION TIMING CONSTANTS
--------------------------------------------------------------------------------
local ANIM = {
    LIFT_DURATION = 0.12,       -- Card lift on drag start
    CARD_MOVE = 0.25,           -- Cards shifting for gap during drag
    DROP_MOVE = 0.18,           -- Drag frame settling to landing position
    DROP_FADE = 0.08,           -- Drag frame fade out after drop
    DROP_FADE_FALLBACK = 0.15,  -- Fallback fade when position unavailable
    CARD_SETTLE = 0.2,          -- Cards settling after drop
    CARD_FADE_IN = 0.3,         -- Sequential fade-in on tab switch
    CARD_STAGGER = 0.08,        -- Delay between cards on tab switch
    PROGRESS_FILL = 0.8,        -- Progress bar animation duration
    TOTALS_FILL = 1.0,          -- Totals bar animation duration
}

--------------------------------------------------------------------------------
-- EXPORT TO NAMESPACE
--------------------------------------------------------------------------------
HonorLog.Animation = {
    AnimateValue = AnimateValue,
    CancelAnimation = CancelAnimation,
    CancelAllAnimations = CancelAllAnimations,
    EaseOutQuad = EaseOutQuad,
    EaseInOutQuad = EaseInOutQuad,
    ANIM = ANIM,
}
