-- StatsHUD.local.lua
-- Place this LocalScript in StarterGui (or StarterPlayerScripts) to auto-create the HUD for each player.
-- Features:
--  - Bottom-left modern HUD with 5 stat boxes (Health, Armor, Hunger, Thirst, Stamina)
--  - Smooth value tweening, glow, gradients, UIStroke (ApplyStrokeMode = Border)
--  - Demo bindings: H = damage health, J = damage armor, K = reduce hunger, L = reduce thirst
--  - Hold LeftShift to drain stamina; release to regen after 2s
--  - Public API functions: setHealth, setArmor, setHunger, setThirst, setStamina

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Config
local HUD_NAME = "StatsHUD"
local MAIN_FRAME_SIZE = UDim2.new(0, 320, 0, 50)
local MAIN_FRAME_POSITION = UDim2.new(0.02, 0, 0.98, 0)
local MAIN_FRAME_ANCHOR = Vector2.new(0, 1)
local BOX_SIZE = UDim2.new(0, 50, 0, 50)
local BOX_BG_COLOR = Color3.fromRGB(28, 28, 32)
local BOX_BG_TRANSPARENCY = 0.2
local UICORNER_RADIUS = 6

-- Stat definitions (left to right)
local StatDefs = {
	{ key = "Health",  icon = "❤️", color = Color3.fromRGB(255,70,70), max = 100 },
	{ key = "Armor",   icon = "🛡️", color = Color3.fromRGB(70,170,255), max = 100 },
	{ key = "Hunger",  icon = "🍗", color = Color3.fromRGB(255,200,60), max = 100 },
	{ key = "Thirst",  icon = "💧", color = Color3.fromRGB(255,165,0), max = 100 }, -- thirst uses orange tint for RP taste
	{ key = "Stamina", icon = "💧", color = Color3.fromRGB(60,255,170), max = 100 }, -- stamina green droplet
}

-- State & UI tables
local Stats = {}
local UI = {}

-- Helper to create instances succinctly
local function new(className, props)
	local inst = Instance.new(className)
	if props then
		for k,v in pairs(props) do
			inst[k] = v
		end
	end
	return inst
end

-- Create main HUD frame
local screenGui = new("ScreenGui", {
	Name = HUD_NAME,
	Parent = playerGui,
	DisplayOrder = 1000,
	ResetOnSpawn = false,
})

local mainFrame = new("Frame", {
	Name = "Main",
	Parent = screenGui,
	AnchorPoint = MAIN_FRAME_ANCHOR,
	Position = MAIN_FRAME_POSITION,
	Size = MAIN_FRAME_SIZE,
	BackgroundTransparency = 1,
	ZIndex = 2,
})

-- Container for stat boxes
local container = new("Frame", {
	Name = "Container",
	Parent = mainFrame,
	AnchorPoint = Vector2.new(0,0),
	Position = UDim2.new(0,0,0,0),
	Size = UDim2.new(1,1,1,0),
	BackgroundTransparency = 1,
})
-- Padding and layout
local padding = new("UIPadding", {
	Parent = container,
	PaddingLeft = UDim.new(0, 4),
	PaddingRight = UDim.new(0, 4),
	PaddingTop = UDim.new(0, 0),
	PaddingBottom = UDim.new(0, 0),
})
local layout = new("UIListLayout", {
	Parent = container,
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Left,
	SortOrder = Enum.SortOrder.LayoutOrder,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 8),
})
container:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() end)

-- Helper: creates a stat box (returns table with references)
local function createStatBox(def, order)
	local box = new("Frame", {
		Name = def.key .. "Box",
		Parent = container,
		Size = BOX_SIZE,
		BackgroundColor3 = BOX_BG_COLOR,
		BackgroundTransparency = BOX_BG_TRANSPARENCY,
		LayoutOrder = order,
		ClipsDescendants = false,
	})
	-- Corner
	local corner = new("UICorner", { Parent = box, CornerRadius = UDim.new(0, UICORNER_RADIUS) })
	-- Stroke with ApplyStrokeMode = Border
	local stroke = new("UIStroke", {
		Parent = box,
		Thickness = 2,
		Color = def.color,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
	-- Subtle gradient
	local gradient = new("UIGradient", {
		Parent = box,
		Color = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Color3.fromRGB(40,40,44)),
			ColorSequenceKeypoint.new(1, BOX_BG_COLOR),
		},
		Rotation = 90,
	})

	-- Glow: a slightly transparent duplicate frame behind the box content that will be used for soft glow
	local glow = new("Frame", {
		Name = "Glow",
		Parent = box,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 42, 0, 42),
		BackgroundColor3 = def.color,
		BackgroundTransparency = 0.85,
		ZIndex = 1,
	})
	new("UICorner", { Parent = glow, CornerRadius = UDim.new(0, UICORNER_RADIUS) })

	-- Icon (using emoji/text for simplicity)
	local icon = new("TextLabel", {
		Name = "Icon",
		Parent = box,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.4, 0),
		Size = UDim2.new(0, 24, 0, 24),
		BackgroundTransparency = 1,
		Text = def.icon,
		TextColor3 = Color3.new(1,1,1),
		Font = Enum.Font.GothamBold,
		TextSize = 20,
		ZIndex = 3,
	})
	-- Soft duplicate for glow behind icon
	local iconGlow = new("TextLabel", {
		Name = "IconGlow",
		Parent = box,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.4, 0),
		Size = UDim2.new(0, 34, 0, 34),
		BackgroundTransparency = 1,
		Text = def.icon,
		TextColor3 = def.color,
		Font = Enum.Font.GothamBold,
		TextSize = 28,
		TextTransparency = 0.85,
		ZIndex = 2,
	})
	-- Value label under the icon
	local valueLabel = new("TextLabel", {
		Name = "Value",
		Parent = box,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 2),
		Size = UDim2.new(0, 60, 0, 14),
		BackgroundTransparency = 1,
		Text = "100",
		TextColor3 = Color3.new(1,1,1),
		TextStrokeTransparency = 0.5,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
	})

	-- Put some accessibility attributes
	box:SetAttribute("Stat", def.key)

	return {
		Box = box,
		Corner = corner,
		Stroke = stroke,
		Gradient = gradient,
		Glow = glow,
		Icon = icon,
		IconGlow = iconGlow,
		ValueLabel = valueLabel,
		Def = def,
	}
end

-- Create the stat boxes and associated NumberValues for smooth tweening
for i,def in ipairs(StatDefs) do
	local ui = createStatBox(def, i)
	UI[def.key] = ui

	-- NumberValue to store current displayed value (so we can tween it)
	local nv = new("NumberValue", {
		Name = def.key .. "Value",
		Value = def.max,
		Parent = ui.Box,
	})
	Stats[def.key] = {
		Value = def.max,
		Max = def.max,
		NV = nv,
		UI = ui,
	}
	-- Initialize label
	ui.ValueLabel.Text = tostring(math.floor(nv.Value))
end

-- Helper to tween numeric stat values smoothly
local function tweenStatTo(key, newValue, duration)
	duration = duration or 0.35
	local stat = Stats[key]
	if not stat then return end
	newValue = math.clamp(newValue, 0, stat.Max)
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(stat.NV, tweenInfo, { Value = newValue })
	tween:Play()
	-- While tweening, update label on NV change
	local conn
	conn = stat.NV.Changed:Connect(function()
		local display = math.floor(stat.NV.Value + 0.5)
		stat.UI.ValueLabel.Text = tostring(display)
	end)
	tween.Completed:Connect(function()
		if conn then conn:Disconnect() end
		stat.Value = newValue
		stat.NV.Value = newValue
		stat.UI.ValueLabel.Text = tostring(math.floor(newValue))
	end)
end

-- Public setter functions
local function setHealth(v) tweenStatTo("Health", v) end
local function setArmor(v)  tweenStatTo("Armor", v)  end
local function setHunger(v) tweenStatTo("Hunger", v) end
local function setThirst(v) tweenStatTo("Thirst", v) end
local function setStamina(v) tweenStatTo("Stamina", v) end

-- Helper visual responses

-- Health low: flash red overlay + heartbeat effect
local function handleHealthVisual()
	local stat = Stats.Health
	local ui = stat.UI
	local lowThreshold = stat.Max * 0.2
	-- Create overlay if not present
	if not ui.Box:FindFirstChild("LowOverlay") then
		local overlay = new("Frame", {
			Name = "LowOverlay",
			Parent = ui.Box,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0.5, 0, 0),
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundColor3 = Color3.fromRGB(255,0,0),
			BackgroundTransparency = 1,
			ZIndex = 4,
		})
		new("UICorner", { Parent = overlay, CornerRadius = UDim.new(0, UICORNER_RADIUS) })
	end
	local overlay = ui.Box:FindFirstChild("LowOverlay")
	if stat.Value <= lowThreshold then
		-- start heartbeat (scale pulse) and red flash overlay
		TweenService:Create(overlay, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0.85 }):Play()
		-- heartbeat: pulse icon glow
		local pulse = TweenService:Create(ui.IconGlow, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { TextTransparency = 0.6 })
		pulse:Play()
		ui.HeartbeatTween = pulse
	else
		-- stop heartbeat and hide overlay
		if ui.HeartbeatTween then
			ui.HeartbeatTween:Cancel()
			ui.IconGlow.TextTransparency = 0.85
			ui.HeartbeatTween = nil
		end
		TweenService:Create(overlay, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	end
end

-- Armor damage flash and break effect
local function flashArmorDamage(amount)
	local stat = Stats.Armor
	local ui = stat.UI
	-- Quick blue flash on the stroke and glow
	local origColor = ui.Stroke.Color
	local flashTween = TweenService:Create(ui.Stroke, TweenInfo.new(0.12), { Color = Color3.fromRGB(160, 200, 255) })
	local restoreTween = TweenService:Create(ui.Stroke, TweenInfo.new(0.4), { Color = stat.Def.color })
	flashTween:Play()
	flashTween.Completed:Wait()
	restoreTween:Play()
	-- If armor is 0, create break effect
	if stat.Value <= 0 then
		-- Small radial fade effect: clone glow and expand
		local frag = ui.Glow:Clone()
		frag.Name = "ArmorBreak"
		frag.Parent = ui.Box
		frag.Size = UDim2.new(0, 10, 0, 10)
		frag.BackgroundTransparency = 0.6
		frag.ZIndex = 1
		local breakTween = TweenService:Create(frag, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(0, 90, 0, 90), BackgroundTransparency = 1 })
		breakTween:Play()
		breakTween.Completed:Connect(function() frag:Destroy() end)
	end
end

-- Stamina drain/regenerate logic
local staminaDraining = false
local staminaRegenScheduled = false
local staminaRegenDelay = 2 -- seconds
local staminaDrainRate = 20  -- per second
local staminaRegenRate = 18  -- per second

local function startStaminaDrain()
	if staminaDraining then return end
	staminaDraining = true
	staminaRegenScheduled = false
	-- drain while Shift held
	local last = tick()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not staminaDraining then
			conn:Disconnect()
			return
		end
		local now = tick()
		local dt = now - last
		last = now
		local stat = Stats.Stamina
		local newv = math.max(0, stat.Value - staminaDrainRate * dt)
		tweenStatTo("Stamina", newv, 0.12)
		-- low color change
		if newv <= stat.Max * 0.15 then
			-- flash orange tint
			stat.UI.Stroke.Color = Color3.fromRGB(255,165,0)
			stat.UI.IconGlow.TextColor3 = Color3.fromRGB(255,165,0)
		end
		if newv <= 0 then
			-- empty flashes
			-- blink the value label
			local blinkTween = TweenService:Create(stat.UI.ValueLabel, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { TextTransparency = 0.6 })
			blinkTween:Play()
			stat.UI.EmptyBlink = blinkTween
		end
	end)
end

local function scheduleStaminaRegen()
	if staminaRegenScheduled then return end
	staminaRegenScheduled = true
	delay(staminaRegenDelay, function()
		staminaDraining = false
		-- stop any empty blink
		local stat = Stats.Stamina
		if stat.UI.EmptyBlink then
			stat.UI.EmptyBlink:Cancel()
			stat.UI.ValueLabel.TextTransparency = 0
			stat.UI.EmptyBlink = nil
		end
		-- regen loop
		local last = tick()
		local conn
		conn = RunService.Heartbeat:Connect(function()
			-- stop if we started draining again
			if staminaDraining then
				conn:Disconnect()
				return
			end
			local now = tick()
			local dt = now - last
			last = now
			local stat = Stats.Stamina
			if stat.Value >= stat.Max then
				-- restore stroke color
				stat.UI.Stroke.Color = stat.Def.color
				stat.UI.IconGlow.TextColor3 = stat.Def.color
				conn:Disconnect()
				return
			end
			local newv = math.min(stat.Max, stat.Value + staminaRegenRate * dt)
			tweenStatTo("Stamina", newv, 0.15)
			-- while regening, restore color gradually
			stat.UI.Stroke.Color = stat.Def.color:Lerp(Color3.fromRGB(255,165,0), 0.5)
		end)
		staminaRegenScheduled = false
	end)
end

-- Key bindings for demo interactions (H, J, K, L) and LeftShift for stamina
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.UserInputType == Enum.UserInputType.Keyboard then
		local key = input.KeyCode
		if key == Enum.KeyCode.H then
			-- take health damage demo
			local stat = Stats.Health
			local newv = math.max(0, stat.Value - 18)
			tweenStatTo("Health", newv, 0.4)
			-- if low, trigger visuals
			stat.Value = newv
			handleHealthVisual()
		elseif key == Enum.KeyCode.J then
			-- armor damage
			local stat = Stats.Armor
			local newv = math.max(0, stat.Value - 30)
			tweenStatTo("Armor", newv, 0.25)
			stat.Value = newv
			flashArmorDamage(30)
		elseif key == Enum.KeyCode.K then
			local stat = Stats.Hunger
			local newv = math.max(0, stat.Value - 12)
			tweenStatTo("Hunger", newv, 0.3)
			stat.Value = newv
		elseif key == Enum.KeyCode.L then
			local stat = Stats.Thirst
			local newv = math.max(0, stat.Value - 15)
			tweenStatTo("Thirst", newv, 0.3)
			stat.Value = newv
		elseif key == Enum.KeyCode.LeftShift then
			startStaminaDrain()
		end
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.LeftShift then
		-- schedule regen after delay
		scheduleStaminaRegen()
	end
end)

-- Connect stat NV changes to logic handlers
for name,stat in pairs(Stats) do
	stat.NV.Changed:Connect(function()
		-- store the value for logic checks
		stat.Value = stat.NV.Value
		if name == "Health" then
			handleHealthVisual()
			-- health flashing when low (quick red pulse on icon)
			if stat.Value <= stat.Max * 0.2 then
				-- handled in handleHealthVisual
			end
		elseif name == "Armor" then
			-- if armor just reached zero, run break effect
			if stat.Value <= 0 then
				flashArmorDamage(0)
			end
		end
	end)
end

-- Initialize visuals according to starting values
for name,stat in pairs(Stats) do
	stat.Value = stat.NV.Value
	stat.UI.ValueLabel.Text = tostring(math.floor(stat.Value))
	stat.UI.Stroke.Color = stat.Def.color
	stat.UI.IconGlow.TextColor3 = stat.Def.color
end

-- Expose API to other scripts (setters)
local module = {}
module.setHealth = setHealth
module.setArmor = setArmor
module.setHunger = setHunger
module.setThirst = setThirst
module.setStamina = setStamina
-- Also expose a table to query current stats
module.Stats = Stats
-- Attach module to the ScreenGui so other LocalScripts can require() it via GetAttribute or findfirstchild? 
-- Since LocalScripts can't be required directly via ScreenGui, we'll place a ModuleScript if you prefer. For now we put these functions on the ScreenGui attributes for simplicity.
screenGui:SetAttribute("API_available", true)
-- For convenience, store functions on the GUI (callable via :Invoke on BindableFunction if needed)
-- But simplest: other local scripts can search for this ScreenGui and call these via BindableFunction or by sending RemoteEvents.
-- We'll create a BindableFunction for basic setting calls (local only)
local binder = new("BindableFunction", { Name = "StatsAPICall", Parent = screenGui })
binder.OnInvoke = function(action, value)
	if action == "Health" then setHealth(value)
	elseif action == "Armor" then setArmor(value)
	elseif action == "Hunger" then setHunger(value)
	elseif action == "Thirst" then setThirst(value)
	elseif action == "Stamina" then setStamina(value)
	else
		warn("Unknown Stats API call:", action)
	end
end

-- Demo: brief tween to slightly pop in the HUD on spawn
do
	local origPos = mainFrame.Position
	mainFrame.Position = mainFrame.Position + UDim2.new(0, 0, 0.05, 0)
	local inTween = TweenService:Create(mainFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = origPos })
	inTween:Play()
end

-- End of script. Use the provided API functions to integrate with your game's systems.
-- Example usage from another LocalScript (client-side):
-- local gui = Player.PlayerGui:WaitForChild("StatsHUD")
-- local binder = gui:FindFirstChild("StatsAPICall")
-- binder:Invoke("Health", 78) -- sets health to 78 smoothly
