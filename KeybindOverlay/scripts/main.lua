--[[
    KeybindOverlay - Half Sword
    Press F6 to toggle. Edit config below to customize.
--]]

local UEHelpers = require("UEHelpers")

local TOGGLE_KEY = Key.F6
local TOGGLE_MODIFIERS = {}
local SHOW_ON_START = true
local OVERLAY_POSITION = "topleft" -- topleft, topright, bottomleft, bottomright, center, top, bottom
local FONT_SIZE = 12
local BG_OPACITY = 0.0 -- 0.0 = transparent, 1.0 = solid black

local DefaultKeybinds = {
    {category = "MOVEMENT"},
    {action = "Move Forward",       key = "W"},
    {action = "Move Left",          key = "A"},
    {action = "Move Back",          key = "S"},
    {action = "Move Right",         key = "D"},
    {action = "Run",                key = "Left Shift"},
    {action = "Crouch",             key = "Left Ctrl"},

    {category = "COMBAT"},
    {action = "Right Hand Swing",   key = "LMB"},
    {action = "Right Hand Grab",    key = "E"},
    {action = "Left Hand Swing",    key = "RMB"},
    {action = "Left Hand Grab",     key = "Q"},
    {action = "Thrust Mode",        key = "Left Alt"},
    {action = "Swap Hands",         key = "X"},

    {category = "OTHER"},
    {action = "Inventory",          key = "R"},
    {action = "Arrow Time",         key = "F"},
    {action = "Lock on Target",     key = "Z"},
    {action = "Give Up",            key = "G"},
    {action = "Photo Mode",         key = "C"},
    {action = "Switch View",        key = "V"},
}

local overlayVisible = SHOW_ON_START
local activeKeybinds = DefaultKeybinds
local usingRuntimeBindings = false
local widgetCreated = false
local widgetCanvas, widgetText, widgetHud

local currentDevice = "keyboard"   
local deviceHookActive = false
local kbKeybinds  = {}
local gpKeybinds  = {}

local VIS_INTERACTIVE = 4
local VIS_HIDDEN = 2

local NameOverrides = {
    ["Action_Gallary"]     = "Gallery",
    ["Action_Gallery"]     = "Gallery",
    ["Crouch Hold"]        = "Crouch (Hold)",
    ["Crouch Key"]         = "Crouch",
    ["Toggle Camera Lock"] = "Lock Camera",
    ["Thrust Gamepad"]     = nil,
}

local KeyOverrides = {
    ["LeftShift"]        = "L.Shift",
    ["RightShift"]       = "R.Shift",
    ["LeftControl"]      = "L.Ctrl",
    ["RightControl"]     = "R.Ctrl",
    ["LeftAlt"]          = "L.Alt",
    ["RightAlt"]         = "R.Alt",
    ["SpaceBar"]         = "Space",
    ["LeftMouseButton"]  = "LMB",
    ["RightMouseButton"] = "RMB",
    ["MiddleMouseButton"]= "MMB",
    ["Left"]             = "Left Arrow",
    ["Right"]            = "Right Arrow",
    ["Up"]               = "Up Arrow",
    ["Down"]             = "Down Arrow",
    ["Gamepad_FaceButton_Bottom"]  = "A",
    ["Gamepad_FaceButton_Right"]   = "B",
    ["Gamepad_FaceButton_Left"]    = "X",
    ["Gamepad_FaceButton_Top"]     = "Y",
    ["Gamepad_LeftTrigger"]        = "LT",
    ["Gamepad_RightTrigger"]       = "RT",
    ["Gamepad_LeftTriggerAxis"]    = "LT",
    ["Gamepad_RightTriggerAxis"]   = "RT",
    ["Gamepad_LeftShoulder"]       = "LB",
    ["Gamepad_RightShoulder"]      = "RB",
    ["Gamepad_LeftThumbstick"]     = "LS",
    ["Gamepad_RightThumbstick"]    = "RS",
    ["Gamepad_Special_Left"]       = "Select",
    ["Gamepad_Special_Right"]      = "Menu",
    ["Gamepad_DPad_Up"]            = "D-Up",
    ["Gamepad_DPad_Down"]          = "D-Down",
    ["Gamepad_DPad_Left"]          = "D-Left",
    ["Gamepad_DPad_Right"]         = "D-Right",
    ["Gamepad_LeftX"]              = "L.Stick",
    ["Gamepad_LeftY"]              = "L.Stick",
    ["Gamepad_RightX"]             = "R.Stick",
    ["Gamepad_RightY"]             = "R.Stick",
}

local function PrettifyName(raw)
    if NameOverrides[raw] ~= nil then return NameOverrides[raw] end
    for k, v in pairs(NameOverrides) do
        if k == raw and v == nil then return nil end
    end
    local name = raw
    name = name:gsub("^Action_", ""):gsub("^Key ", ""):gsub("^Key_", ""):gsub("^Axis_", "")
    name = name:gsub("_", " "):gsub("(%l)(%u)", "%1 %2")
    return name:match("^%s*(.-)%s*$")
end

local function PrettifyKey(raw)
    return KeyOverrides[raw] or raw:gsub("(%l)(%u)", "%1 %2")
end

local function ReadInputBindings()
    local kb, gp, found = {}, {}, false

    local ok, err = pcall(function()
        local settings = StaticFindObject("/Script/Engine.Default__InputSettings")
        if not settings or not settings:IsValid() then return end

        local function CollectMappings(mappingsArray, category, filterMouseFromKb)
            if not mappingsArray or not mappingsArray:IsValid() or mappingsArray:GetArrayNum() == 0 then return end

            local kbMap, kbOrder = {}, {}
            local gpMap, gpOrder = {}, {}
            local anyKb, anyGp   = false, false
            local nameField = (category == "ACTIONS") and "ActionName" or "AxisName"

            for i = 1, mappingsArray:GetArrayNum() do
                local m = mappingsArray[i]
                if m then
                    local name, key
                    pcall(function() name = m[nameField]:ToString() end)
                    pcall(function() key  = m.Key.KeyName:ToString() end)

                    if name and key and key ~= "None" then
                        local isGamepad = key:find("Gamepad") ~= nil

                        if isGamepad then
                            if not gpMap[name] then gpMap[name] = {}; table.insert(gpOrder, name) end
                            table.insert(gpMap[name], key)
                            anyGp = true
                        else
                            if not filterMouseFromKb or not key:find("Mouse") then
                                if not kbMap[name] then kbMap[name] = {}; table.insert(kbOrder, name) end
                                table.insert(kbMap[name], key)
                                anyKb = true
                            end
                        end
                    end
                end
            end

            local function FlushTable(targetList, srcMap, srcOrder, cat)
                if not next(srcMap) then return end
                table.insert(targetList, {category = cat})
                for _, name in ipairs(srcOrder) do
                    local display = PrettifyName(name)
                    if display then
                        local keys = {}
                        for _, k in ipairs(srcMap[name]) do table.insert(keys, PrettifyKey(k)) end
                        table.insert(targetList, {action = display, key = table.concat(keys, " / ")})
                    end
                end
            end

            if anyKb then FlushTable(kb, kbMap, kbOrder, category); found = true end
            if anyGp then FlushTable(gp, gpMap, gpOrder, category); found = true end
        end

        CollectMappings(settings.ActionMappings, "ACTIONS",  false)
        CollectMappings(settings.AxisMappings,   "MOVEMENT", true)
    end)

    return kb, gp, found
end

local function LoadKeybinds()
    local kb, gp, found = ReadInputBindings()
    if found then
        kbKeybinds = (#kb > 0) and kb or DefaultKeybinds
        gpKeybinds = (#gp > 0) and gp or {}
        usingRuntimeBindings = true
    else
        kbKeybinds = DefaultKeybinds
        gpKeybinds = {}
        usingRuntimeBindings = false
    end
    activeKeybinds = (currentDevice == "gamepad" and #gpKeybinds > 0)
                     and gpKeybinds or kbKeybinds
end

local function BuildOverlayText()
    local lines = {}
    local src = usingRuntimeBindings and "LIVE" or "config"
    local dev = (currentDevice == "gamepad") and "GAMEPAD" or "KB+M"
    table.insert(lines, "=== KEYBINDS [" .. dev .. "] (" .. src .. ") ===  [F6 hide]")
    table.insert(lines, "")

    for _, entry in ipairs(activeKeybinds) do
        if entry.category then
            table.insert(lines, "--- " .. entry.category .. " ---")
        elseif entry.action and entry.key then
            table.insert(lines, "  " .. entry.action .. "  [" .. entry.key .. "]")
        end
    end

    return table.concat(lines, "\n")
end

local function RefreshOverlayText()
    if not widgetCreated then return end
    pcall(function()
        if widgetText and widgetText:IsValid() then
            widgetText:SetText(FText(BuildOverlayText()))
        end
    end)
end

local function OnDeviceInput(self, key, event, amountDepressed, bGamepad)
    local keyName = ""
    pcall(function() keyName = key:get().KeyName:ToString() end)
    if keyName == "" then return end

    local newDevice = keyName:find("Gamepad") and "gamepad" or "keyboard"
    if newDevice == currentDevice then return end

    currentDevice = newDevice
    local gpAvailable = gpKeybinds and #gpKeybinds > 0
    activeKeybinds = (currentDevice == "gamepad" and gpAvailable)
                     and gpKeybinds or kbKeybinds

    if overlayVisible then
        RefreshOverlayText()
    end
end

pcall(function()
    RegisterHook("/Script/Engine.PlayerController:InputKey", OnDeviceInput)
    deviceHookActive = true
end)

local function RGBA(r, g, b, a) return {R = r, G = g, B = b, A = a} end

local function CreateWidget()
    if widgetCreated and widgetCanvas and widgetCanvas:IsValid() then return true end

    local ok, err = pcall(function()
        local gi = UEHelpers.GetGameInstance()
        if not gi or not gi:IsValid() then return end

        local cls = {
            widget = StaticFindObject("/Script/UMG.UserWidget"),
            tree   = StaticFindObject("/Script/UMG.WidgetTree"),
            canvas = StaticFindObject("/Script/UMG.CanvasPanel"),
            border = StaticFindObject("/Script/UMG.Border"),
            text   = StaticFindObject("/Script/UMG.TextBlock"),
        }

        widgetHud = StaticConstructObject(cls.widget, gi, FName("KeybindHUD"))
        if not widgetHud or not widgetHud:IsValid() then return end

        widgetHud.WidgetTree = StaticConstructObject(cls.tree, widgetHud, FName("KeybindTree"))
        widgetCanvas = StaticConstructObject(cls.canvas, widgetHud.WidgetTree, FName("KeybindCanvas"))
        widgetHud.WidgetTree.RootWidget = widgetCanvas

        local border = StaticConstructObject(cls.border, widgetCanvas, FName("KeybindBorder"))
        border:SetBrushColor(RGBA(0, 0, 0, BG_OPACITY))
        border:SetPadding({Left = 15, Top = 10, Right = 15, Bottom = 10})

        widgetText = StaticConstructObject(cls.text, border, FName("KeybindText"))
        widgetText.Font.Size = FONT_SIZE
        widgetText:SetColorAndOpacity({SpecifiedColor = RGBA(1, 1, 1, 1), ColorUseRule = 0})
        widgetText:SetShadowOffset({X = 1, Y = 1})
        widgetText:SetShadowColorAndOpacity(RGBA(0, 0, 0, 0.8))
        widgetText:SetText(FText(BuildOverlayText()))

        border:SetContent(widgetText)
        local slot = widgetCanvas:AddChildToCanvas(border)
        slot:SetAutoSize(true)

        local positions = {
            center      = {anchor = {0.5, 0.5}, align = {0.5, 0.5}, pos = {0, 0}},
            top         = {anchor = {0.5, 0},   align = {0.5, 0},   pos = {0, 10}},
            bottom      = {anchor = {0.5, 1},   align = {0.5, 1},   pos = {0, -10}},
            topleft     = {anchor = {0, 0},     align = {0, 0},     pos = {10, 10}},
            topright    = {anchor = {1, 0},     align = {1, 0},     pos = {-10, 10}},
            bottomleft  = {anchor = {0, 1},     align = {0, 1},     pos = {10, -10}},
            bottomright = {anchor = {1, 1},     align = {1, 1},     pos = {-10, -10}},
        }

        local p = positions[OVERLAY_POSITION] or positions.topleft
        slot:SetAnchors({Minimum = {X = p.anchor[1], Y = p.anchor[2]}, Maximum = {X = p.anchor[1], Y = p.anchor[2]}})
        slot:SetAlignment({X = p.align[1], Y = p.align[2]})
        slot:SetPosition({X = p.pos[1], Y = p.pos[2]})

        widgetCanvas.Visibility = VIS_INTERACTIVE
        border.Visibility = VIS_INTERACTIVE
        widgetText.Visibility = VIS_INTERACTIVE

        widgetHud:AddToViewport(99)
        widgetCreated = true
    end)

    if not ok then return false end
    return widgetCreated
end

local function SetVisible(visible)
    if not widgetCanvas or not widgetCanvas:IsValid() then return end
    pcall(function()
        widgetCanvas:SetVisibility(visible and VIS_INTERACTIVE or VIS_HIDDEN)
    end)
end

local function EnsureOverlay()
    if widgetCreated then
        local valid = false
        pcall(function() valid = widgetCanvas and widgetCanvas:IsValid() end)
        if not valid then
            widgetCreated = false
            widgetCanvas, widgetText, widgetHud = nil, nil, nil
        end
    end

    if not widgetCreated then
        LoadKeybinds()
        CreateWidget()
        SetVisible(overlayVisible)
    end
end

RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    ExecuteInGameThreadWithDelay(500, function() EnsureOverlay() end)
end)

LoopAsync(2000, function()
    ExecuteInGameThread(function()
        local ready = false
        pcall(function()
            local pc = UEHelpers.GetPlayerController()
            ready = pc and pc:IsValid()
        end)
        if ready then EnsureOverlay() end
    end)
    return false
end)

RegisterKeyBindAsync(TOGGLE_KEY, TOGGLE_MODIFIERS, function()
    overlayVisible = not overlayVisible
    if overlayVisible then
        if not widgetCreated then
            ExecuteInGameThread(function()
                LoadKeybinds()
                CreateWidget()
                SetVisible(true)
            end)
        else
            ExecuteInGameThread(function()
                RefreshOverlayText()
                SetVisible(true)
            end)
        end
    else
        SetVisible(false)
    end
end)

