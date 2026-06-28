-- StatsHUD.local.lua
-- Revised HUD per request:
--  - Removed demo bindings and removed Armor/Thirst (only Health, Stamina, Hunger remain)
--  - Smaller boxes by default; box size is editable via SetBoxSize(px)
--  - Stamina only drains while sprinting (use SprintStart/SprintStop). Walking does not drain stamina.
--  - Stamina regen delay and rate are editable via SetRates
--  - Health dies when it reaches 0 (sets Humanoid.Health = 0) and regenerates over time if not damaged; regen delay and rate are editable.
--  - Hunger only regenerates when consumeFood(amount) is called.
--  - Smooth downward-depleting fills implemented (Fill frames anchored to bottom). Tweens animate size smoothly.
--  - Public API via BindableFunction StatsAPICall: actions include Set, Damage, ConsumeFood, SprintStart/Stop, SetBoxSize, SetRates.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- CONFIG (editable)
local HUD_NAME = "StatsHUD"
local MAIN_FRAME_POSITION = UDim2.new(0.02, 0, 0.98, 0)
local MAIN_FRAME_ANCHOR = Vector2.new(0, 1)
local BOX_PIXEL_SIZE = 44 -- default; editable via SetBoxSize(px)
local BOX_BG_COLOR = Color3.fromRGB(28, 28, 32)
local BOX_BG_TRANSPARENCY = 0.2
local UICORNER_RADIUS = 6
local SPACING = 8
local PADDING = 4
local VALUE_LABEL_HEIGHT = 14

-- Stamina settings (editable at runtime via API)
local stamina = {
    Max = 100,
    DrainRate = 20, -- per second when sprinting
    RegenRate = 18, -- per second when not sprinting
    RegenDelay = 2, -- seconds after stop sprinting before regen begins
}

-- Health settings
local healthSettings = {
    Max = 100,
    RegenRate = 6, -- per second when not recently damaged
    RegenDelay = 4, -- seconds after last damage before regen begins
}

-- Hunger settings
local hungerSettings = {
    Max = 100,
    -- No auto regeneration; only via ConsumeFood
}

-- Internal state
local Stats = {} -- will hold Health, Stamina, Hunger data
local UI = {}
local sprinting = false
local staminaRegenScheduled = false
local lastDamageTime = 0

-- Utility to create Instances
local function new(className, props)
    local inst = Instance.new(className)
    if props then
        for k,v in pairs(props) do inst[k] = v end
    end
    return inst
end

-- Build or rebuild the HUD
local function buildHUD()
    -- Remove existing if present
    local existing = playerGui:FindFirstChild(HUD_NAME)
    if existing then existing:Destroy() end

    local screenGui = new("ScreenGui", {
        Name = HUD_NAME,
        Parent = playerGui,
        DisplayOrder = 1000,
        ResetOnSpawn = false,
    })

    -- compute sizes
    local statCount = 3 -- Health, Hunger, Stamina
    local totalWidth = PADDING*2 + statCount * BOX_PIXEL_SIZE + (statCount - 1) * SPACING
    local totalHeight = BOX_PIXEL_SIZE + VALUE_LABEL_HEIGHT + 6

    local mainFrame = new("Frame", {
        Name = "Main",
        Parent = screenGui,
        AnchorPoint = MAIN_FRAME_ANCHOR,
        Position = MAIN_FRAME_POSITION,
        Size = UDim2.new(0, totalWidth, 0, totalHeight),
        BackgroundTransparency = 1,
        ZIndex = 2,
    })

    local container = new("Frame", {
        Name = "Container",
        Parent = mainFrame,
        AnchorPoint = Vector2.new(0,0),
        Position = UDim2.new(0,0,0,0),
        Size = UDim2.new(1,1,1,0),
        BackgroundTransparency = 1,
    })
    local paddingInst = new("UIPadding", { Parent = container, PaddingLeft = UDim.new(0,PADDING), PaddingRight = UDim.new(0,PADDING) })
    local layout = new("UIListLayout", {
        Parent = container,
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Top,
        Padding = UDim.new(0, SPACING),
    })

    -- Stat definitions in order: Health, Hunger, Stamina
    local defs = {
        { key = "Health",  icon = "❤️", color = Color3.fromRGB(255,70,70), max = healthSettings.Max },
        { key = "Hunger",  icon = "🍗", color = Color3.fromRGB(255,200,60), max = hungerSettings.Max },
        { key = "Stamina", icon = "💧", color = Color3.fromRGB(60,255,170), max = stamina.Max },
    }

    -- create boxes
    for i,def in ipairs(defs) do
        local box = new("Frame", {
            Name = def.key .. "Box",
            Parent = container,
            Size = UDim2.new(0, BOX_PIXEL_SIZE, 0, BOX_PIXEL_SIZE),
            BackgroundColor3 = BOX_BG_COLOR,
            BackgroundTransparency = BOX_BG_TRANSPARENCY,
            LayoutOrder = i,
            ClipsDescendants = true,
        })
        new("UICorner", { Parent = box, CornerRadius = UDim.new(0, UICORNER_RADIUS) })
        local stroke = new("UIStroke", { Parent = box, Thickness = 2, Color = def.color, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
        new("UIGradient", { Parent = box, Color = ColorSequence.new{ ColorSequenceKeypoint.new(0, Color3.fromRGB(40,40,44)), ColorSequenceKeypoint.new(1, BOX_BG_COLOR) }, Rotation = 90 })

        -- Fill frame anchored to bottom: height represents proportion (1.0 = full)
        local fill = new("Frame", {
            Name = "Fill",
            Parent = box,
            AnchorPoint = Vector2.new(0,1),
            Position = UDim2.new(0,1,0,0), -- bottom-left
            Size = UDim2.new(1,0,1,0), -- full initially
            BackgroundColor3 = def.color,
            BackgroundTransparency = 0.85,
            ZIndex = 1,
        })
        new("UICorner", { Parent = fill, CornerRadius = UDim.new(0, UICORNER_RADIUS) })

        -- Icon and glow on top
        local iconGlow = new("TextLabel", {
            Name = "IconGlow",
            Parent = box,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.42, 0),
            Size = UDim2.new(0, BOX_PIXEL_SIZE * 0.6, 0, BOX_PIXEL_SIZE * 0.6),
            BackgroundTransparency = 1,
            Text = def.icon,
            TextColor3 = def.color,
            Font = Enum.Font.GothamBold,
            TextSize = math.clamp(BOX_PIXEL_SIZE * 0.5, 12, 28),
            TextTransparency = 0.9,
            ZIndex = 2,
        })

        local icon = new("TextLabel", {
            Name = "Icon",
            Parent = box,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.42, 0),
            Size = UDim2.new(0, BOX_PIXEL_SIZE * 0.5, 0, BOX_PIXEL_SIZE * 0.5),
            BackgroundTransparency = 1,
            Text = def.icon,
            TextColor3 = Color3.new(1,1,1),
            Font = Enum.Font.GothamBold,
            TextSize = math.clamp(BOX_PIXEL_SIZE * 0.45, 10, 24),
            ZIndex = 3,
        })

        -- Value label below box (positioned inside mainFrame area)
        local valueLabel = new("TextLabel", {
            Name = "Value",
            Parent = UI._ScreenGui and UI._ScreenGui or playerGui, -- temporary placement; will be re-parented later
            AnchorPoint = Vector2.new(0,0),
            Position = UDim2.new(0, (PADDING + (i-1) * (BOX_PIXEL_SIZE + SPACING)), 0, BOX_PIXEL_SIZE + 2),
            Size = UDim2.new(0, BOX_PIXEL_SIZE, 0, VALUE_LABEL_HEIGHT),
            BackgroundTransparency = 1,
            Text = tostring(def.max),
            TextColor3 = Color3.new(1,1,1),
            TextStrokeTransparency = 0.5,
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Center,
            ZIndex = 3,
        })

        -- Save UI refs
        UI[def.key] = { Box = box, Fill = fill, Icon = icon, IconGlow = iconGlow, ValueLabel = valueLabel, Stroke = stroke }
    end

    -- store screenGui reference
    UI._ScreenGui = screenGui

    -- Re-parent value labels to mainFrame for accurate positioning
    for i,def in ipairs(UI) do
        -- skip _ScreenGui entry
    end

    -- fix value label parents and positions now that mainFrame exists
    for i,def in ipairs({"Health","Hunger","Stamina"}) do
        local ui = UI[def]
        if ui and ui.ValueLabel then
            ui.ValueLabel.Parent = UI._ScreenGui.Main
            ui.ValueLabel.Position = UDim2.new(0, (PADDING + (i-1) * (BOX_PIXEL_SIZE + SPACING)), 0, BOX_PIXEL_SIZE + 2)
        end
    end
end

-- Initialize stats and UI
local function initStats()
    Stats.Health = { Value = healthSettings.Max, Max = healthSettings.Max }
    Stats.Hunger = { Value = hungerSettings.Max, Max = hungerSettings.Max }
    Stats.Stamina = { Value = stamina.Max, Max = stamina.Max }

    -- Build UI
    buildHUD()

    -- Initialize fills to current values
    for name,stat in pairs(Stats) do
        local ui = UI[name]
        if ui then
            ui.ValueLabel.Text = tostring(math.floor(stat.Value + 0.5))
            local pct = stat.Value / stat.Max
            ui.Fill.Size = UDim2.new(1,0,pct,0)
        end
    end
end

-- Smoothly tween fill to new percent (0..1)
local function tweenFill(name, percent, duration)
    duration = duration or 0.35
    local ui = UI[name]
    if not ui or not ui.Fill then return end
    percent = math.clamp(percent, 0, 1)
    -- We want the fill to shrink downwards. Fill frame is anchored to bottom: increasing height = more filled.
    -- Animate Size.Y.Scale to percent
    local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tween = TweenService:Create(ui.Fill, info, { Size = UDim2.new(1,0,percent,0) })
    tween:Play()
    -- Smooth number update
    local startVal = tonumber(ui.ValueLabel.Text) or 0
    local targetVal = math.floor((Stats[name].Max * percent) + 0.5)
    local diff = targetVal - startVal
    if diff == 0 then return end
    local steps = math.max(6, math.floor(duration * 60))
    for i=1,steps do
        delay((i-1)*(duration/steps), function()
            local t = i/steps
            local v = math.floor(startVal + diff * t + 0.5)
            if ui and ui.ValueLabel then ui.ValueLabel.Text = tostring(v) end
        end)
    end
end

-- Apply stat change functions
local function setStat(name, newValue)
    local stat = Stats[name]
    if not stat then return end
    newValue = math.clamp(newValue, 0, stat.Max)
    stat.Value = newValue
    -- update UI
    local pct = stat.Value / stat.Max
    tweenFill(name, pct, 0.25)
    local ui = UI[name]
    if ui and ui.ValueLabel then ui.ValueLabel.Text = tostring(math.floor(stat.Value + 0.5)) end
    -- special: if health hits 0, attempt to kill player
    if name == "Health" and stat.Value <= 0 then
        local character = player.Character
        if character then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid.Health = 0
            end
        end
    end
end

local function damageHealth(amount)
    amount = math.abs(amount or 0)
    local stat = Stats.Health
    local newv = math.max(0, stat.Value - amount)
    setStat("Health", newv)
    lastDamageTime = tick()
end

local function healHealth(amount)
    amount = math.abs(amount or 0)
    local stat = Stats.Health
    setStat("Health", stat.Value + amount)
end

local function setStaminaValue(v)
    setStat("Stamina", v)
end

local function setHunger(v)
    setStat("Hunger", v)
end

local function consumeFood(amount)
    amount = math.abs(amount or 0)
    local stat = Stats.Hunger
    setStat("Hunger", math.min(stat.Max, stat.Value + amount))
end

-- Sprint control (external movement controller should call these via StatsAPICall)
local staminaDrainConn
local function startSprint()
    if sprinting then return end
    sprinting = true
    -- cancel any regen scheduling
    staminaRegenScheduled = false
    -- start draining via Heartbeat
    if staminaDrainConn then staminaDrainConn:Disconnect() end
    local last = tick()
    staminaDrainConn = RunService.Heartbeat:Connect(function()
        local now = tick()
        local dt = now - last
        last = now
        local stat = Stats.Stamina
        local newv = math.max(0, stat.Value - stamina.DrainRate * dt)
        setStaminaValue(newv)
        -- low tint
        if newv <= stat.Max * 0.15 then
            local ui = UI.Stamina
            if ui then
                ui.Stroke.Color = Color3.fromRGB(255,165,0)
                ui.IconGlow.TextColor3 = Color3.fromRGB(255,165,0)
            end
        end
    end)
end

local function stopSprint()
    if not sprinting then return end
    sprinting = false
    if staminaDrainConn then staminaDrainConn:Disconnect(); staminaDrainConn = nil end
    -- schedule regen after delay
    if not staminaRegenScheduled then
        staminaRegenScheduled = true
        delay(stamina.RegenDelay, function()
            staminaRegenScheduled = false
            -- regen loop
            local last = tick()
            local conn
            conn = RunService.Heartbeat:Connect(function()
                if sprinting then conn:Disconnect(); return end
                local now = tick()
                local dt = now - last
                last = now
                local stat = Stats.Stamina
                if stat.Value >= stat.Max then
                    -- restore visuals
                    local ui = UI.Stamina
                    if ui and ui.Stroke then ui.Stroke.Color = Color3.fromRGB(60,255,170); ui.IconGlow.TextColor3 = Color3.fromRGB(60,255,170) end
                    conn:Disconnect(); return
                end
                local newv = math.min(stat.Max, stat.Value + stamina.RegenRate * dt)
                setStaminaValue(newv)
            end)
        end)
    end
end

-- Health regeneration when not damaged for a period
local healthRegenConn
local function startHealthRegenLoop()
    if healthRegenConn then return end
    healthRegenConn = RunService.Heartbeat:Connect(function(dt)
        local stat = Stats.Health
        if not stat then return end
        local now = tick()
        if stat.Value < stat.Max and (now - lastDamageTime) >= healthSettings.RegenDelay then
            local newv = math.min(stat.Max, stat.Value + healthSettings.RegenRate * dt)
            setStat("Health", newv)
        end
    end)
end

-- Hook into character to attempt to keep server/humanoid synced if possible
local function onCharacterAdded(character)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid:GetPropertyChangedSignal("Health"):Connect(function()
            local h = humanoid.Health
            if h ~= Stats.Health.Value then
                setStat("Health", h)
            end
        end)
    end
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then onCharacterAdded(player.Character) end

-- API BindableFunction for local scripts to call (Set, Damage, ConsumeFood, SprintStart/Stop, SetBoxSize, SetRates)
local function setupAPI()
    local gui = UI._ScreenGui
    if not gui then return end
    local binder = new("BindableFunction", { Name = "StatsAPICall", Parent = gui })
    binder.OnInvoke = function(action, ...)
        action = tostring(action or "")
        if action == "Set" then
            local name, value = ...
            if Stats[name] then setStat(name, tonumber(value) or 0) end
        elseif action == "Damage" then
            local name, value = ...
            if name == "Health" then damageHealth(tonumber(value) or 0) end
        elseif action == "ConsumeFood" then
            local amount = ...
            consumeFood(tonumber(amount) or 0)
        elseif action == "SprintStart" then
            startSprint()
        elseif action == "SprintStop" then
            stopSprint()
        elseif action == "SetBoxSize" then
            local px = ...
            px = tonumber(px)
            if px and px >= 20 then
                BOX_PIXEL_SIZE = px
                buildHUD()
                -- reinitialize labels/fills
                for name,stat in pairs(Stats) do
                    local ui = UI[name]
                    if ui and ui.ValueLabel then ui.ValueLabel.Text = tostring(math.floor(stat.Value + 0.5)) end
                    if ui and ui.Fill then ui.Fill.Size = UDim2.new(1,0, stat.Value / stat.Max, 0) end
                end
            end
        elseif action == "SetRates" then
            local t = ... -- expect table-like: { staminaDrain, staminaRegen, staminaRegenDelay, healthRegen, healthRegenDelay }
            if type(t) == "table" then
                stamina.DrainRate = tonumber(t.staminaDrain) or stamina.DrainRate
                stamina.RegenRate = tonumber(t.staminaRegen) or stamina.RegenRate
                stamina.RegenDelay = tonumber(t.staminaRegenDelay) or stamina.RegenDelay
                healthSettings.RegenRate = tonumber(t.healthRegen) or healthSettings.RegenRate
                healthSettings.RegenDelay = tonumber(t.healthRegenDelay) or healthSettings.RegenDelay
            end
        else
            warn("Unknown StatsAPICall action:", action)
        end
    end
end

-- Start loops
initStats()
startHealthRegenLoop()
setupAPI()

-- Expose functions on the ScreenGui as attributes for convenience
local gui = UI._ScreenGui
if gui then
    gui:SetAttribute("API_available", true)
end

-- End of script
