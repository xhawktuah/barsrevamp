# barsrevamp — Stats HUD for Roblox

This repository contains a lightweight, client-side Stats HUD for Roblox that provides a sleek, modern stat display (Health, Hunger, Stamina) intended for easy integration into roleplay experiences.

The main implementation is a LocalScript that auto-creates the HUD in the player's PlayerGui and exposes a simple local API for updating stats and controlling sprinting/consumption behavior.

## Files
- src/StatsHUD.local.lua — LocalScript that builds the HUD and provides the local BindableFunction API.

## Features
- Minimal, modern bottom-left stat HUD with three compact stat boxes (Health, Hunger, Stamina).
- Smooth, downward-depleting fills with tweened animations and readable numeric values.
- Stamina drains only while sprinting and regenerates after an editable delay.
- Health dies when it reaches 0 (attempts to set the player's Humanoid.Health = 0) and regenerates over time when the player has not taken damage for an editable delay.
- Hunger does NOT regenerate automatically — it is increased only when the player consumes food.
- Editable runtime settings: box size, stamina/health rates and delays.

## How to test in Roblox Studio
1. Open your place in Roblox Studio.
2. Copy `src/StatsHUD.local.lua` into `StarterGui` as a LocalScript (or paste its contents into a LocalScript in StarterGui).
3. Play the game (Start > Play). The HUD should appear bottom-left.

## API (local, BindableFunction)
The HUD exposes a BindableFunction named `StatsAPICall` on the `StatsHUD` ScreenGui. You can call it from other LocalScripts or the Command Bar for testing.

Example (Command Bar or another LocalScript):

```lua
local player = game.Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("StatsHUD")
local binder = gui:FindFirstChild("StatsAPICall")

-- Start sprinting (stamina will drain)
binder:Invoke("SprintStart")

-- Stop sprinting (stamina will regen after configured delay)
binder:Invoke("SprintStop")

-- Damage the player
binder:Invoke("Damage", "Health", 30) -- deals 30 damage

-- Set a stat directly
binder:Invoke("Set", "Health", 80) -- set Health to 80

-- Consume food to increase Hunger
binder:Invoke("ConsumeFood", 25) -- adds 25 hunger

-- Change box size:
binder:Invoke("SetBoxSize", 36) -- rebuilds HUD with 36px boxes

-- Update rates/delays:
binder:Invoke("SetRates", {
    staminaDrain = 25,
    staminaRegen = 20,
    staminaRegenDelay = 1.5,
    healthRegen = 8,
    healthRegenDelay = 3,
})
```

Notes
- The provided API is local-only (BindableFunction). For server-authoritative stat updates, consider using RemoteEvents: have the server send stat updates to the client and call the HUD API locally.
- The HUD listens for changes to the player's Humanoid.Health and will reflect server-driven health updates when they occur.
- Icons in the current script use emoji for quick setup. Replace them with ImageLabels (`rbxassetid://...`) if you prefer custom art.

## Integration suggestions
- Call `SprintStart` and `SprintStop` from your movement controller when sprinting begins/ends.
- When the player consumes food (server or client), call `ConsumeFood` to restore hunger locally and/or have the server notify clients of the updated value.
- For authoritative damage handling, apply damage on the server and replicate to clients via RemoteEvents; the HUD will reflect Humanoid.Health changes automatically.

## Contributing
If you'd like additional features (server-driven API, module conversion, image assets, per-stat tooltips, etc.), open an issue or submit a pull request.

## License
MIT — see LICENSE (if you want to add one)
