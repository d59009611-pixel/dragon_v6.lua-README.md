-- BUILD_TARGET: Roblox / Blox Fruits (2753915549, 4442272183, 7449423635)
-- BUILD_ID: DRAGON_2026_11_V6
-- CHANGES v6 (from v5):
--   * CacheParts uses GetDescendants() — accessories covered
--   * SetFlight calls SnapshotCollisionState once (no double CacheParts)
--   * Title on mobile compacted to "DRAGON v5 [=]" (fits 320px)
--   * ApplyPlatformLayout re-reads TopInset when switching to mobile
--   All v5 fixes retained: quest timeout, PartsList noclip cache,
--   iOS inset, boss priority, slider TapMin, NpcPos=nil guard,
--   rename to Dragon, dual-name idempotent guard.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local GuiService        = game:GetService("GuiService")
local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser       = game:GetService("VirtualUser")
local CoreGui           = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

-- === IDEMPOTENT GUARD ===
local genv = (typeof(getgenv) == "function" and getgenv()) or _G
if type(genv.ArgonTeardown) == "function" then
    pcall(genv.ArgonTeardown)
    genv.ArgonTeardown = nil
end
if type(genv.DragonTeardown) == "function" then
    pcall(genv.DragonTeardown)
    genv.DragonTeardown = nil
end

local OverlayParent = (pcall(function() return CoreGui.Name end) and CoreGui)
    or LocalPlayer:WaitForChild("PlayerGui")
do
    for _, guiName in ipairs({ "ArgonRenderSurface", "DragonRenderSurface" }) do
        local old = OverlayParent:FindFirstChild(guiName)
        if old then pcall(function() old:Destroy() end) end
    end
end

pcall(function() VirtualUser:CaptureController() end)

-- === PLATFORM & INSET DETECTION ===
local function DetectPlatform()
    local touch = false
    local kb = true
    pcall(function() touch = UserInputService.TouchEnabled end)
    pcall(function() kb = UserInputService.KeyboardEnabled end)

    local isPhone = touch and not kb
    local isTablet = touch and kb
    local platform = isPhone and "mobile" or (isTablet and "tablet" or "pc")

    local tenFoot = false
    pcall(function() tenFoot = GuiService:IsTenFootInterface() end)

    local platEnumName = ""
    pcall(function()
        if type(UserInputService.GetPlatform) == "function" then
            platEnumName = string.lower(tostring(UserInputService:GetPlatform()))
        end
    end)

    local vpWidth = 1280
    pcall(function()
        local cam = workspace.CurrentCamera
        if cam then vpWidth = math.max(cam.ViewportSize.X, cam.ViewportSize.Y) end
    end)

    local topInset = 0
    pcall(function() topInset = GuiService:GetGuiInset().Y end)

    local isIOS = (tenFoot == false) and touch and (
        string.find(platEnumName, "ios") ~= nil
        or (platEnumName == "" and vpWidth > 700)
    )
    local subPlatform = platform == "pc" and "pc" or (isIOS and "iphone" or "android")
    return platform, subPlatform, isIOS, topInset
end

local detectedPlatform, detectedSubPlatform, detectedIOS, detectedTopInset = DetectPlatform()

-- === CONFIGURATION ===
local CONFIG = {
    ENABLED_ON_LAUNCH       = false,
    TOGGLE_UI_KEY           = Enum.KeyCode.RightShift,
    EXIT_KEY                = Enum.KeyCode.End,
    UPDATE_INTERVAL_MS      = 16,
    CONFIG_FILE_PATH        = "dragon_v5_config.json",
    LEGACY_CONFIG_FILE_PATH = "bf_argon_config.json",
    BUSO_COOLDOWN           = 5.0,
    ATTACK_COOLDOWN         = 0.12,
    QUEST_COOLDOWN          = 2.5,
    QUEST_TIMEOUT           = 5.0,
    NPC_INTERACT_RADIUS     = 8.0,

    PlatformSensitive       = "auto",
    FARM_RANGE              = 2500.0,
    WALK_SPEED              = 16.0,

    LINE_THICKNESS          = 1.5,
    LABEL_FONT_SIZE         = 13,
    LABEL_MIN_FONT_SIZE     = 9,
    LABEL_MAX_FONT_SIZE     = 16,
    DISTANCE_SCALE_REF      = 150.0,
    MAX_RENDER_DISTANCE     = 2500.0,
    FOV_RADIUS              = 180.0,
    DRAW_FOV_CIRCLE         = false,
    FOV_SEGMENTS            = 48,
    CLAMP_TRACERS           = true,
    CORNER_BOX_STYLE        = true,

    COLORS = {
        ENEMY     = { R = 255, G = 75,  B = 75,  A = 0.90 },
        BOSS      = { R = 255, G = 40,  B = 180, A = 0.95 },
        PLAYER    = { R = 70,  G = 190, B = 255, A = 0.90 },
        FRUIT     = { R = 180, G = 95,  B = 255, A = 0.95 },
        CHEST     = { R = 255, G = 215, B = 65,  A = 0.85 },
        FOV_RING  = { R = 200, G = 200, B = 200, A = 0.50 },
        UI_ACCENT = { R = 60,  G = 145, B = 255, A = 1.00 },
        UI_BG     = { R = 16,  G = 18,  B = 22,  A = 0.96 },
        UI_PANEL  = { R = 24,  G = 27,  B = 34,  A = 1.00 },
        UI_TEXT   = { R = 230, G = 235, B = 242, A = 1.00 },
    },

    STATE = {
        MasterEnable        = false,
        TeleportToIsland    = false,
        AutoQuestFarm       = false,
        AutoFarmNearest     = false,
        AutoFarmBosses      = false,
        AutoCollectFruits   = false,
        AutoCollectChests   = false,
        AutoEquipWeapon     = true,
        AutoBusoHaki        = true,
        FastAttack          = true,
        FarmDistanceOffset  = 14.0,
        MoveSpeed           = 260.0,
        SelectedWeaponType  = "Melee",
        SelectedIsland      = "None",

        EspEnemies          = false,
        EspPlayers          = false,
        EspFruits           = false,
        EspChests           = false,
        DrawBoxes           = true,
        DrawTracers         = false,
        DrawLabels          = true,
        DrawHealthBar       = true,
    }
}

local TARGET = {
    ENEMIES_FOLDER     = "Enemies",
    FRUIT_MATCH        = "Fruit",
    CHEST_MATCH        = "Chest",
    REMOTE_CONTAINER   = "Remotes",
    PRIMARY_RPC        = "CommF_",
    COLLECT_FOLDERS    = { "ChestModels", "Fruits", "SpawnedFruits", "FruitModels" },
    ISLANDS = {
        ["Starter Island"]    = Vector3.new(1071.28, 16.30, 1426.86),
        ["Jungle"]            = Vector3.new(-1602.52, 36.85, 153.28),
        ["Marine Fortress"]   = Vector3.new(-4505.37, 20.68, 4260.55),
        ["Sky Island"]        = Vector3.new(-4869.10, 733.46, -2667.01),
        ["Cafe (Sea 2)"]      = Vector3.new(-380.47, 77.22, 255.82),
        ["Kingdom of Rose"]   = Vector3.new(-425.12, 72.90, 1835.40),
        ["Green Zone"]        = Vector3.new(-2448.53, 73.01, -3210.63),
        ["Mansion (Sea 3)"]   = Vector3.new(-12548.72, 337.19, -7481.42),
        ["Castle on the Sea"] = Vector3.new(-5074.45, 314.51, -3015.62),
    },
    QUESTS = {
        ["Starter Island"]  = { QuestName = "BanditQuest1",  Level = 1, NpcPos = Vector3.new(1059.10, 16.30, 1548.55), MobName = "Bandit" },
        ["Jungle"]          = { QuestName = "JungleQuest",   Level = 1, NpcPos = Vector3.new(-1601.20, 36.85, 153.60), MobName = "Gorilla" },
        ["Marine Fortress"] = { QuestName = "MarineQuest",   Level = 1, NpcPos = Vector3.new(-4505.10, 20.68, 4260.70), MobName = "Marine" },
    },
}

local Runtime = {
    Active = true,
    FirstFrameVerified = false,
    Platform = detectedPlatform,
    SubPlatform = detectedSubPlatform,
    IsIOS = detectedIOS,
    TopInset = detectedTopInset,
    DrawerOpen = false,
    Connections = {},
    BusoTask = nil,
    QuestTask = nil,
    FlightActive = false,
    FlightTarget = nil,
    FlightTick = 0,
    CollideState = nil,
    PartsList = nil,
    LinePool = {},
    LabelPool = {},
    LineIndex = 0,
    LabelIndex = 0,
    LastBuso = 0,
    LastAttack = 0,
    LastLogic = 0,
    LastQuest = 0,
    FruitCache = {},
    ChestCache = {},
    HookedFolders = {},
    CounterLabel = nil,
}

local function Track(c)
    table.insert(Runtime.Connections, c)
    return c
end

local function ToColor3(c)
    return Color3.fromRGB(c.R, c.G, c.B)
end

local function BrightenColor3(c3, delta)
    local d = delta or 10
    return Color3.fromRGB(
        math.clamp(math.floor(c3.R * 255 + d), 0, 255),
        math.clamp(math.floor(c3.G * 255 + d), 0, 255),
        math.clamp(math.floor(c3.B * 255 + d), 0, 255)
    )
end

local function ClampScreenPoint(v, vp)
    return Vector2.new(math.clamp(v.X, 0, vp.X), math.clamp(v.Y, 0, vp.Y))
end

local function FormatVec3(v)
    if not v then return "0,0,0" end
    return string.format("%.1f,%.1f,%.1f", v.X, v.Y, v.Z)
end

local function ParseVec3(str)
    if type(str) ~= "string" then return nil end
    local x, y, z = string.match(str, "^%s*([%-%.%d]+)%s*,%s*([%-%.%d]+)%s*,%s*([%-%.%d]+)%s*$")
    local nx, ny, nz = tonumber(x), tonumber(y), tonumber(z)
    if nx and ny and nz then
        return Vector3.new(nx, ny, nz)
    end
    return nil
end

local function ActiveQuestEntry()
    local island = CONFIG.STATE.SelectedIsland
    if not TARGET.QUESTS[island] then
        island = "Starter Island"
    end
    return TARGET.QUESTS[island], island
end

-- === METRICS ===
local function metrics()
    local p = Runtime.Platform
    local topInset = Runtime.TopInset or 0
    if p == "mobile" then
        local top = math.max(8, topInset + 4)
        return {
            WindowSize       = UDim2.new(1, -16, 1, -top - 8),
            WindowPos        = UDim2.new(0, 8, 0, top),
            HeaderHeight     = 40,
            FontSize         = 14,
            HeaderFontSize   = 14,
            RowHeight        = 44,
            ButtonHeight     = 44,
            SliderHeight     = 54,
            InputHeight      = 48,
            TabButtonHeight  = 44,
            SidebarWidth     = 175,
            ScrollThickness  = 0,
            Padding          = 10,
            TapMin           = 44,
            UseDrawer        = true,
        }
    elseif p == "tablet" then
        return {
            WindowSize       = UDim2.fromOffset(480, 380),
            WindowPos        = UDim2.new(0.5, -240, 0.5, -190),
            HeaderHeight     = 36,
            FontSize         = 13,
            HeaderFontSize   = 14,
            RowHeight        = 34,
            ButtonHeight     = 34,
            SliderHeight     = 44,
            InputHeight      = 38,
            TabButtonHeight  = 36,
            SidebarWidth     = 140,
            ScrollThickness  = 3,
            Padding          = 8,
            TapMin           = 32,
            UseDrawer        = false,
        }
    else
        return {
            WindowSize       = UDim2.fromOffset(540, 420),
            WindowPos        = UDim2.new(0.5, -270, 0.5, -210),
            HeaderHeight     = 32,
            FontSize         = 12,
            HeaderFontSize   = 13,
            RowHeight        = 28,
            ButtonHeight     = 28,
            SliderHeight     = 38,
            InputHeight      = 32,
            TabButtonHeight  = 34,
            SidebarWidth     = 150,
            ScrollThickness  = 3,
            Padding          = 6,
            TapMin           = 28,
            UseDrawer        = false,
        }
    end
end

-- === PROJECTION ===
local function WorldToScreen(worldPos)
    local cam = workspace.CurrentCamera
    if not cam then return nil, false, 0 end
    local sp, on = cam:WorldToViewportPoint(worldPos)
    if sp.Z <= 0.05 then return nil, false, sp.Z end
    return Vector2.new(sp.X, sp.Y), on, sp.Z
end

local function GetBox(rootPart, scaleY)
    if not rootPart then return nil end
    local half = (scaleY or 5.5) * 0.5
    local top = rootPart.Position + Vector3.new(0, half + 1.0, 0)
    local bot = rootPart.Position - Vector3.new(0, half + 0.5, 0)
    local ts, tOn, tz = WorldToScreen(top)
    local bs, bOn, bz = WorldToScreen(bot)
    if not ts or not bs or tz <= 0.05 or bz <= 0.05 then return nil end
    if not tOn and not bOn then return nil end
    local h = math.abs(bs.Y - ts.Y)
    if h < 2 then return nil end
    local w = h * 0.62
    local cx = (ts.X + bs.X) * 0.5
    return {
        X = cx - w * 0.5, Y = ts.Y, W = w, H = h,
        CenterBottom = Vector2.new(cx, bs.Y),
        CenterTop = Vector2.new(cx, ts.Y),
        Distance = tz
    }
end

-- === SURFACE ===
local RootGui = Instance.new("ScreenGui")
RootGui.Name = "DragonRenderSurface"
RootGui.IgnoreGuiInset = true
RootGui.ResetOnSpawn = false
RootGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
RootGui.Parent = OverlayParent

local Canvas = Instance.new("Frame")
Canvas.Name = "Dragon_Canvas"
Canvas.BackgroundTransparency = 1
Canvas.Size = UDim2.new(1, 0, 1, 0)
Canvas.Active = false
Canvas.Parent = RootGui

local ToastHost = Instance.new("Frame")
ToastHost.Name = "DragonToastHost"
ToastHost.BackgroundTransparency = 1
ToastHost.AnchorPoint = Vector2.new(1, 1)
ToastHost.Position = UDim2.new(1, -14, 1, -14)
ToastHost.Size = UDim2.fromOffset(290, 200)
ToastHost.Active = false
ToastHost.Parent = RootGui

local ToastLayout = Instance.new("UIListLayout")
ToastLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
ToastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
ToastLayout.Padding = UDim.new(0, 6)
ToastLayout.Parent = ToastHost

local function AddToast(text, duration)
    if not RootGui or not ToastHost then return end
    local m = metrics()
    local card = Instance.new("Frame")
    card.Name = "DRAGON_Toast"
    card.Size = UDim2.fromOffset(270, math.max(32, m.RowHeight - 6))
    card.BackgroundColor3 = ToColor3(CONFIG.COLORS.UI_PANEL)
    card.BackgroundTransparency = 0.08
    card.BorderSizePixel = 0
    card.Parent = ToastHost

    local stroke = Instance.new("UIStroke")
    stroke.Color = ToColor3(CONFIG.COLORS.UI_ACCENT)
    stroke.Thickness = 1
    stroke.Parent = card

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = card

    local lbl = Instance.new("TextLabel")
    lbl.Name = "DRAGON_ToastLabel"
    lbl.Size = UDim2.new(1, -16, 1, 0)
    lbl.Position = UDim2.fromOffset(8, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.RobotoMono
    lbl.TextSize = m.FontSize
    lbl.TextColor3 = ToColor3(CONFIG.COLORS.UI_TEXT)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextTruncate = Enum.TextTruncate.AtEnd
    lbl.Text = "[*] DRAGON: " .. tostring(text)
    lbl.Parent = card

    task.delay(duration or 2.0, function()
        if not card or not card.Parent then return end
        pcall(function()
            local tw = TweenService:Create(card, TweenInfo.new(0.18), { BackgroundTransparency = 1 })
            tw:Play()
        end)
        task.delay(0.2, function()
            if card and card.Parent then
                pcall(function() card:Destroy() end)
            end
        end)
    end)
end

local function AcquireLine()
    Runtime.LineIndex = Runtime.LineIndex + 1
    local l = Runtime.LinePool[Runtime.LineIndex]
    if not l then
        l = Instance.new("Frame")
        l.AnchorPoint = Vector2.new(0.5, 0.5)
        l.BorderSizePixel = 0
        l.Parent = Canvas
        Runtime.LinePool[Runtime.LineIndex] = l
    end
    l.Visible = true
    return l
end

local function DrawLine(p1, p2, col, th)
    local d = p2 - p1
    local len = d.Magnitude
    if len < 0.5 then return end
    local l = AcquireLine()
    l.Position = UDim2.fromOffset((p1.X + p2.X) * 0.5, (p1.Y + p2.Y) * 0.5)
    l.Size = UDim2.fromOffset(len, th or CONFIG.LINE_THICKNESS)
    l.Rotation = math.deg(math.atan2(d.Y, d.X))
    l.BackgroundColor3 = ToColor3(col)
    l.BackgroundTransparency = 1.0 - (col.A or 1.0)
end

local function DrawTracer(from, to, col)
    local cam = workspace.CurrentCamera
    if not cam then return end
    local endpoint = CONFIG.CLAMP_TRACERS and ClampScreenPoint(to, cam.ViewportSize) or to
    DrawLine(from, endpoint, col, 1.0)
end

local function DrawBox(b, col, hp)
    local x, y, w, h, t = b.X, b.Y, b.W, b.H, CONFIG.LINE_THICKNESS
    if CONFIG.CORNER_BOX_STYLE then
        local cw, ch = math.max(4, w * 0.28), math.max(4, h * 0.28)
        DrawLine(Vector2.new(x, y), Vector2.new(x + cw, y), col, t)
        DrawLine(Vector2.new(x, y), Vector2.new(x, y + ch), col, t)
        DrawLine(Vector2.new(x + w - cw, y), Vector2.new(x + w, y), col, t)
        DrawLine(Vector2.new(x + w, y), Vector2.new(x + w, y + ch), col, t)
        DrawLine(Vector2.new(x, y + h - ch), Vector2.new(x, y + h), col, t)
        DrawLine(Vector2.new(x, y + h), Vector2.new(x + cw, y + h), col, t)
        DrawLine(Vector2.new(x + w - cw, y + h), Vector2.new(x + w, y + h), col, t)
        DrawLine(Vector2.new(x + w, y + h - ch), Vector2.new(x + w, y + h), col, t)
    else
        DrawLine(Vector2.new(x, y), Vector2.new(x + w, y), col, t)
        DrawLine(Vector2.new(x + w, y), Vector2.new(x + w, y + h), col, t)
        DrawLine(Vector2.new(x + w, y + h), Vector2.new(x, y + h), col, t)
        DrawLine(Vector2.new(x, y + h), Vector2.new(x, y), col, t)
    end
    if CONFIG.STATE.DrawHealthBar and hp then
        local r = math.clamp(hp, 0, 1)
        local bx = x - 5
        DrawLine(Vector2.new(bx, y), Vector2.new(bx, y + h), { R = 20, G = 20, B = 20, A = 0.8 }, 3)
        DrawLine(
            Vector2.new(bx, y + h * (1 - r)),
            Vector2.new(bx, y + h),
            { R = math.floor(255 * (1 - r)), G = math.floor(255 * r), B = 45, A = 0.95 },
            2
        )
    end
end

local function DrawLabel(pos, text, dist, col)
    Runtime.LabelIndex = Runtime.LabelIndex + 1
    local lbl = Runtime.LabelPool[Runtime.LabelIndex]
    if not lbl then
        lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.RobotoMono
        lbl.TextStrokeTransparency = 0.25
        lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
        lbl.AnchorPoint = Vector2.new(0.5, 0)
        lbl.Size = UDim2.fromOffset(220, 20)
        lbl.Parent = Canvas
        Runtime.LabelPool[Runtime.LabelIndex] = lbl
    end
    local scale = math.clamp(CONFIG.DISTANCE_SCALE_REF / math.max(dist, 1), 0.65, 1.25)
    local fs = math.clamp(math.floor(CONFIG.LABEL_FONT_SIZE * scale), CONFIG.LABEL_MIN_FONT_SIZE, CONFIG.LABEL_MAX_FONT_SIZE)
    lbl.Visible = true
    lbl.Position = UDim2.fromOffset(pos.X, pos.Y + 2)
    lbl.TextSize = fs
    lbl.TextColor3 = ToColor3(col)
    lbl.TextTransparency = 1.0 - (col.A or 1.0)
    lbl.Text = text
end

local function DrawCircle(c, r, seg, col)
    local step = (math.pi * 2) / seg
    local prev = Vector2.new(c.X + r, c.Y)
    for i = 1, seg do
        local a = i * step
        local nxt = Vector2.new(c.X + math.cos(a) * r, c.Y + math.sin(a) * r)
        DrawLine(prev, nxt, col, 1.2)
        prev = nxt
    end
end

local function ResetPool()
    for i = Runtime.LineIndex + 1, #Runtime.LinePool do Runtime.LinePool[i].Visible = false end
    for i = Runtime.LabelIndex + 1, #Runtime.LabelPool do Runtime.LabelPool[i].Visible = false end
    Runtime.LineIndex, Runtime.LabelIndex = 0, 0
end

-- === COLLECTIBLES ===
local function UpdateCollectCounterUI()
    if Runtime.CounterLabel then
        Runtime.CounterLabel.Text = string.format(
            "  Cached Fruits: %d | Chests: %d",
            #Runtime.FruitCache,
            #Runtime.ChestCache
        )
    end
end

local function AddCollectibleCandidate(obj)
    if not obj or not (obj:IsA("Model") or obj:IsA("BasePart")) then return end
    if string.find(obj.Name, TARGET.FRUIT_MATCH) then
        if not table.find(Runtime.FruitCache, obj) then
            table.insert(Runtime.FruitCache, obj)
            UpdateCollectCounterUI()
        end
    elseif string.find(obj.Name, TARGET.CHEST_MATCH) then
        if not table.find(Runtime.ChestCache, obj) then
            table.insert(Runtime.ChestCache, obj)
            UpdateCollectCounterUI()
        end
    end
end

local function RemoveCollectibleCandidate(obj)
    local changed = false
    for i = #Runtime.FruitCache, 1, -1 do
        if Runtime.FruitCache[i] == obj then
            table.remove(Runtime.FruitCache, i)
            changed = true
        end
    end
    for i = #Runtime.ChestCache, 1, -1 do
        if Runtime.ChestCache[i] == obj then
            table.remove(Runtime.ChestCache, i)
            changed = true
        end
    end
    if changed then UpdateCollectCounterUI() end
end

local function BindCollectibleFolder(folder)
    if not folder or Runtime.HookedFolders[folder] then return end
    Runtime.HookedFolders[folder] = true
    for _, child in ipairs(folder:GetChildren()) do
        AddCollectibleCandidate(child)
    end
    Track(folder.ChildAdded:Connect(AddCollectibleCandidate))
    Track(folder.ChildRemoved:Connect(RemoveCollectibleCandidate))
end

local function RefreshCollectibles()
    Runtime.FruitCache = {}
    Runtime.ChestCache = {}
    for _, obj in ipairs(workspace:GetChildren()) do
        AddCollectibleCandidate(obj)
    end
    for _, fname in ipairs(TARGET.COLLECT_FOLDERS) do
        local folder = workspace:FindFirstChild(fname)
        if folder then
            BindCollectibleFolder(folder)
        end
    end
    UpdateCollectCounterUI()
end

Track(workspace.ChildAdded:Connect(function(obj)
    AddCollectibleCandidate(obj)
    if table.find(TARGET.COLLECT_FOLDERS, obj.Name) then
        BindCollectibleFolder(obj)
    end
end))

Track(workspace.ChildRemoved:Connect(function(obj)
    RemoveCollectibleCandidate(obj)
    Runtime.HookedFolders[obj] = nil
end))

-- === CONFIG PERSISTENCE ===
local function SaveConfig()
    local qEntry, qIsland = ActiveQuestEntry()
    local payload = {
        STATE               = CONFIG.STATE,
        PlatformSensitive   = CONFIG.PlatformSensitive,
        FARM_RANGE          = CONFIG.FARM_RANGE,
        WALK_SPEED          = CONFIG.WALK_SPEED,
        MAX_RENDER_DISTANCE = CONFIG.MAX_RENDER_DISTANCE,
        FOV_RADIUS          = CONFIG.FOV_RADIUS,
        DRAW_FOV_CIRCLE     = CONFIG.DRAW_FOV_CIRCLE,
        CORNER_BOX_STYLE    = CONFIG.CORNER_BOX_STYLE,
        CLAMP_TRACERS       = CONFIG.CLAMP_TRACERS,
        CUSTOM_QUEST        = qEntry and {
            Island    = qIsland,
            QuestName = qEntry.QuestName,
            Level     = qEntry.Level,
            NpcPos    = FormatVec3(qEntry.NpcPos),
            MobName   = qEntry.MobName,
        } or nil,
    }
    local ok, enc = pcall(function() return HttpService:JSONEncode(payload) end)
    if ok and enc and typeof(writefile) == "function" then
        pcall(writefile, CONFIG.CONFIG_FILE_PATH, enc)
        AddToast("Saved " .. CONFIG.CONFIG_FILE_PATH, 2.0)
    else
        AddToast("Encoded (writefile unavailable)", 2.0)
    end
end

local function LoadConfig()
    if typeof(isfile) ~= "function" or typeof(readfile) ~= "function" then
        AddToast("readfile unavailable in executor", 2.0)
        return false
    end

    local targetPath = nil
    local okNew, exNew = pcall(isfile, CONFIG.CONFIG_FILE_PATH)
    if okNew and exNew then
        targetPath = CONFIG.CONFIG_FILE_PATH
    else
        local okOld, exOld = pcall(isfile, CONFIG.LEGACY_CONFIG_FILE_PATH)
        if okOld and exOld then
            targetPath = CONFIG.LEGACY_CONFIG_FILE_PATH
        end
    end

    if not targetPath then
        AddToast("No saved config file found", 2.0)
        return false
    end

    local rOk, content = pcall(readfile, targetPath)
    if not (rOk and content) then return false end
    local dOk, dec = pcall(function() return HttpService:JSONDecode(content) end)
    if not (dOk and type(dec) == "table") then return false end
    if type(dec.STATE) == "table" then
        for k, v in pairs(dec.STATE) do
            if CONFIG.STATE[k] ~= nil then CONFIG.STATE[k] = v end
        end
    end
    for _, key in ipairs({
        "PlatformSensitive", "FARM_RANGE", "WALK_SPEED",
        "MAX_RENDER_DISTANCE", "FOV_RADIUS", "DRAW_FOV_CIRCLE",
        "CORNER_BOX_STYLE", "CLAMP_TRACERS"
    }) do
        if dec[key] ~= nil then CONFIG[key] = dec[key] end
    end
    if type(dec.CUSTOM_QUEST) == "table" and dec.CUSTOM_QUEST.Island then
        local targetEntry = TARGET.QUESTS[dec.CUSTOM_QUEST.Island]
        if targetEntry then
            if type(dec.CUSTOM_QUEST.QuestName) == "string" then
                targetEntry.QuestName = dec.CUSTOM_QUEST.QuestName
            end
            local parsedVec = ParseVec3(dec.CUSTOM_QUEST.NpcPos)
            if parsedVec then
                targetEntry.NpcPos = parsedVec
            end
        end
    end
    if CONFIG.PlatformSensitive ~= "auto" and (
        CONFIG.PlatformSensitive == "pc"
        or CONFIG.PlatformSensitive == "tablet"
        or CONFIG.PlatformSensitive == "mobile"
    ) then
        Runtime.Platform = CONFIG.PlatformSensitive
    else
        Runtime.Platform = detectedPlatform
    end
    AddToast("Loaded " .. targetPath, 2.0)
    return true
end

-- === GAMEPLAY ===
local function GetRoot(model)
    if not model then return nil, nil end
    return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart,
           model:FindFirstChildOfClass("Humanoid")
end

local function EquipWeapon(cat)
    local char = LocalPlayer.Character
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if not char or not bp then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    for _, item in ipairs(bp:GetChildren()) do
        if item:IsA("Tool") then
            local tt = item.ToolTip or ""
            if tt == cat or (cat == "Melee" and (tt == "" or string.find(item.Name, "Melee"))) then
                hum:EquipTool(item)
                return
            end
        end
    end
end

local function FastAttack()
    local now = os.clock()
    if (now - Runtime.LastAttack) < CONFIG.ATTACK_COOLDOWN then return end
    Runtime.LastAttack = now
    pcall(function() VirtualUser:Button1Down(Vector2.zero) end)
    task.delay(0.03, function()
        pcall(function() VirtualUser:Button1Up(Vector2.zero) end)
    end)
end

local function TryBuso()
    local char = LocalPlayer.Character
    if not char then return end
    if char:FindFirstChild("HasBuso") then return end
    if Runtime.BusoTask then return end
    local now = os.clock()
    if (now - Runtime.LastBuso) < CONFIG.BUSO_COOLDOWN then return end
    Runtime.LastBuso = now
    local remotes = ReplicatedStorage:FindFirstChild(TARGET.REMOTE_CONTAINER)
    local comm = remotes and remotes:FindFirstChild(TARGET.PRIMARY_RPC)
    if not (comm and comm:IsA("RemoteFunction")) then return end
    Runtime.BusoTask = task.spawn(function()
        pcall(function() comm:InvokeServer("Buso") end)
        Runtime.BusoTask = nil
    end)
end

-- FIX v6: GetDescendants covers accessory Model children inside the character
local function CacheParts(char)
    if not char then return end
    Runtime.CollideState = Runtime.CollideState or {}
    local parts = {}
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then
            parts[p] = true
            if Runtime.CollideState[p] == nil then
                Runtime.CollideState[p] = p.CanCollide
            end
        end
    end
    Runtime.PartsList = parts
end

local function SnapshotCollisionState(char)
    if not char then return end
    CacheParts(char)
end

local function EnforceNoClipStep()
    if not Runtime.Active or not Runtime.FlightActive
       or not CONFIG.STATE.MasterEnable then return end
    if not Runtime.PartsList then
        CacheParts(LocalPlayer.Character)
        if not Runtime.PartsList then return end
    end
    for p in pairs(Runtime.PartsList) do
        if p.Parent and p.CanCollide then
            pcall(function() p.CanCollide = false end)
        end
    end
end

local function RestoreCollision()
    if not Runtime.CollideState then
        Runtime.PartsList = nil
        return
    end
    for p, s in pairs(Runtime.CollideState) do
        if p and p.Parent then
            pcall(function() p.CanCollide = s end)
        end
    end
    Runtime.CollideState = nil
    Runtime.PartsList = nil
end

local function SetFlight(targetCFrame)
    Runtime.FlightTarget = targetCFrame
    Runtime.FlightTick = Runtime.FlightTick + 1
    local char = LocalPlayer.Character
    if not Runtime.FlightActive then
        Runtime.FlightActive = true
        -- FIX v6: single snapshot call (was CacheParts + SnapshotCollisionState twice)
        SnapshotCollisionState(char)
    end
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then hum.PlatformStand = true end
end

local function StopFlight()
    if not Runtime.FlightActive and not Runtime.CollideState then return end
    Runtime.FlightActive = false
    Runtime.FlightTarget = nil
    RestoreCollision()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then hum.PlatformStand = false end
end

Track(LocalPlayer.CharacterAdded:Connect(function(newChar)
    Runtime.FlightActive = false
    Runtime.FlightTarget = nil
    Runtime.CollideState = nil
    Runtime.PartsList = nil
    task.defer(function()
        if newChar and newChar.Parent then
            CacheParts(newChar)
        end
    end)
end))

local function TickFlight(dt)
    if not Runtime.FlightActive or not Runtime.FlightTarget then return end
    local char = LocalPlayer.Character
    local hrp, hum = GetRoot(char)
    if not hrp or not hum or hum.Health <= 0 then StopFlight(); return end
    local cur = hrp.Position
    local tgt = Runtime.FlightTarget.Position
    local dist = (tgt - cur).Magnitude
    if dist <= 1.5 then
        hrp.CFrame = Runtime.FlightTarget
        hrp.AssemblyLinearVelocity = Vector3.zero
        return
    end
    local stepDist = math.min(dist, CONFIG.STATE.MoveSpeed * dt)
    local dir = (tgt - cur).Unit
    hrp.CFrame = CFrame.new(cur + dir * stepDist, tgt)
    hrp.AssemblyLinearVelocity = Vector3.zero
end

local function FindBestEnemy(bossOnly, questMobName)
    local char = LocalPlayer.Character
    local myHrp = char and char:FindFirstChild("HumanoidRootPart")
    if not myHrp then return nil end
    local folder = workspace:FindFirstChild(TARGET.ENEMIES_FOLDER)
    if not folder then return nil end
    local best, bestDist = nil, math.min(CONFIG.FARM_RANGE or math.huge, math.huge)
    for _, mob in ipairs(folder:GetChildren()) do
        if mob:IsA("Model") then
            local hrp, hum = GetRoot(mob)
            if hrp and hum and hum.Health > 0 then
                local isBoss = (hum.MaxHealth >= 50000) or string.find(mob.Name, "Boss") ~= nil
                local ok = false
                if questMobName then
                    ok = (mob.Name == questMobName)
                elseif bossOnly then
                    ok = isBoss
                else
                    ok = true
                end
                if ok then
                    local d = (hrp.Position - myHrp.Position).Magnitude
                    if d < bestDist then bestDist, best = d, mob end
                end
            end
        end
    end
    return best
end

local function GetCollectiblePos(cache, myHrp)
    if not myHrp then return nil end
    local best, bestDist = nil, math.huge
    for i = #cache, 1, -1 do
        local obj = cache[i]
        if not obj or not obj.Parent then
            table.remove(cache, i)
        else
            local part = obj:IsA("BasePart") and obj or obj:FindFirstChild("Handle") or obj.PrimaryPart
            if part and part:IsA("BasePart") then
                local d = (part.Position - myHrp.Position).Magnitude
                if d < bestDist then bestDist, best = d, part end
            end
        end
    end
    return best
end

local function GetQuestVisible()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local main = pg and pg:FindFirstChild("Main")
    local quest = main and main:FindFirstChild("Quest")
    return quest and quest.Visible or false
end

local function FireQuestStart(questInfo)
    if Runtime.QuestTask then return end
    local remotes = ReplicatedStorage:FindFirstChild(TARGET.REMOTE_CONTAINER)
    local comm = remotes and remotes:FindFirstChild(TARGET.PRIMARY_RPC)
    if not (comm and comm:IsA("RemoteFunction")) then return end
    local now = os.clock()
    if (now - Runtime.LastQuest) < CONFIG.QUEST_COOLDOWN then return end
    Runtime.LastQuest = now

    local qt
    qt = task.spawn(function()
        pcall(function()
            comm:InvokeServer("StartQuest", questInfo.QuestName, questInfo.Level)
        end)
        if Runtime.QuestTask == qt then Runtime.QuestTask = nil end
    end)
    Runtime.QuestTask = qt
    task.delay(CONFIG.QUEST_TIMEOUT or 5.0, function()
        if Runtime.QuestTask == qt then
            pcall(function() task.cancel(qt) end)
            Runtime.QuestTask = nil
        end
    end)
end

-- === UI CONSTRUCTION ===
local UIRefs = {
    Refresh = {}, Rows = {}, Buttons = {}, Sliders = {},
    Inputs = {}, TabButtons = {}, Pages = {},
}

local function BindHoverEffect(guiObj, getBaseColor)
    Track(guiObj.MouseEnter:Connect(function()
        guiObj.BackgroundColor3 = BrightenColor3(getBaseColor(), 10)
    end))
    Track(guiObj.MouseLeave:Connect(function()
        guiObj.BackgroundColor3 = getBaseColor()
    end))
end

local Main = Instance.new("Frame")
Main.Name = "DragonMain"
Main.BackgroundColor3 = ToColor3(CONFIG.COLORS.UI_BG)
Main.BorderSizePixel = 0
Main.Active = true
Main.ClipsDescendants = true
Main.Parent = RootGui
do
    local s = Instance.new("UIStroke")
    s.Color = ToColor3(CONFIG.COLORS.UI_ACCENT); s.Thickness = 1; s.Parent = Main
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 4); c.Parent = Main
end

local Header = Instance.new("Frame")
Header.Name = "Header"
Header.BackgroundColor3 = ToColor3(CONFIG.COLORS.UI_PANEL)
Header.BorderSizePixel = 0
Header.ZIndex = 5
Header.Parent = Main

local LockBadge = Instance.new("TextLabel")
LockBadge.Name = "LockBadge"
LockBadge.BackgroundTransparency = 1
LockBadge.Font = Enum.Font.RobotoMono
LockBadge.TextColor3 = ToColor3(CONFIG.COLORS.UI_ACCENT)
LockBadge.Text = "[*]"
LockBadge.ZIndex = 6
LockBadge.Parent = Header

local Title = Instance.new("TextLabel")
Title.Name = "Title"
Title.BackgroundTransparency = 1
Title.Font = Enum.Font.RobotoMono
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.TextColor3 = ToColor3(CONFIG.COLORS.UI_TEXT)
Title.TextTruncate = Enum.TextTruncate.AtEnd
Title.ZIndex = 6
Title.Parent = Header

do
    local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
    Track(Header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = Main.Position
        end
    end))
    Track(Header.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end))
    Track(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input == dragInput
            or input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
            local absSize = Main.AbsoluteSize
            local newX = startPos.X.Offset + d.X
            local newY = startPos.Y.Offset + d.Y
            if startPos.X.Scale == 0 then
                newX = math.clamp(newX, 0, math.max(0, vp.X - absSize.X))
            end
            if startPos.Y.Scale == 0 then
                newY = math.clamp(newY, 0, math.max(0, vp.Y - absSize.Y))
            end
            Main.Position = UDim2.new(startPos.X.Scale, newX, startPos.Y.Scale, newY)
        end
    end))
    Track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
end

local DrawerBackdrop = Instance.new("TextButton")
DrawerBackdrop.Name = "DrawerBackdrop"
DrawerBackdrop.BackgroundColor3 = Color3.new(0, 0, 0)
DrawerBackdrop.BackgroundTransparency = 1
DrawerBackdrop.BorderSizePixel = 0
DrawerBackdrop.Text = ""
DrawerBackdrop.Visible = false
DrawerBackdrop.AutoButtonColor = false
DrawerBackdrop.ZIndex = 7
DrawerBackdrop.Parent = Main

local TabBar = Instance.new("Frame")
TabBar.Name = "TabBar"
TabBar.BackgroundColor3 = ToColor3(CONFIG.COLORS.UI_PANEL)
TabBar.BorderSizePixel = 0
TabBar.ZIndex = 8
TabBar.Parent = Main

local TabLayout = Instance.new("UIListLayout")
TabLayout.Padding = UDim.new(0, 4)
TabLayout.SortOrder = Enum.SortOrder.LayoutOrder
TabLayout.Parent = TabBar

local Content = Instance.new("Frame")
Content.Name = "Content"
Content.BackgroundTransparency = 1
Content.ZIndex = 2
Content.Parent = Main

local DrawerButton = nil
local SetDrawerState = nil

local function AddDrawerToggle(header, tabBar, backdrop)
    local btn = Instance.new("TextButton")
    btn.Name = "DrawerToggle"
    btn.Size = UDim2.fromOffset(44, 40)
    btn.Position = UDim2.fromOffset(4, 0)
    btn.BackgroundColor3 = Color3.fromRGB(34, 39, 48)
    btn.BorderSizePixel = 0
    btn.Font = Enum.Font.RobotoMono
    btn.TextSize = 14
    btn.TextColor3 = ToColor3(CONFIG.COLORS.UI_TEXT)
    btn.Text = "[=]"
    btn.AutoButtonColor = false
    btn.ZIndex = 7
    btn.Parent = header
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 4); c.Parent = btn

    BindHoverEffect(btn, function()
        return Runtime.DrawerOpen and ToColor3(CONFIG.COLORS.UI_ACCENT) or Color3.fromRGB(34, 39, 48)
    end)

    SetDrawerState = function(open)
        local m = metrics()
        Runtime.DrawerOpen = open
        if not m.UseDrawer then
            backdrop.Visible = false
            tabBar.Position = UDim2.fromOffset(0, m.HeaderHeight)
            return
        end
        btn.BackgroundColor3 = open and ToColor3(CONFIG.COLORS.UI_ACCENT) or Color3.fromRGB(34, 39, 48)
        if open then
            backdrop.Visible = true
            TweenService:Create(backdrop, TweenInfo.new(0.15), { BackgroundTransparency = 0.45 }):Play()
            TweenService:Create(tabBar, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Position = UDim2.fromOffset(0, m.HeaderHeight)
            }):Play()
        else
            TweenService:Create(backdrop, TweenInfo.new(0.15), { BackgroundTransparency = 1 }):Play()
            TweenService:Create(tabBar, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                Position = UDim2.fromOffset(-m.SidebarWidth - 10, m.HeaderHeight)
            }):Play()
            task.delay(0.16, function()
                if not Runtime.DrawerOpen and backdrop then backdrop.Visible = false end
            end)
        end
    end

    Track(btn.MouseButton1Click:Connect(function()
        SetDrawerState(not Runtime.DrawerOpen)
    end))
    Track(backdrop.MouseButton1Click:Connect(function()
        SetDrawerState(false)
    end))
    return btn
end

DrawerButton = AddDrawerToggle(Header, TabBar, DrawerBackdrop)

local Pages, Tabs = {}, {}
local ActiveTabName = nil

local function MakeTab(name, order)
    local m = metrics()
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, m.TabButtonHeight)
    btn.BackgroundColor3 = Color3.fromRGB(30, 34, 42)
    btn.BorderSizePixel = 0
    btn.Font = Enum.Font.RobotoMono
    btn.TextSize = m.FontSize
    btn.TextColor3 = ToColor3(CONFIG.COLORS.UI_TEXT)
    btn.Text = "  " .. name
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.AutoButtonColor = false
    btn.LayoutOrder = order
    btn.ZIndex = 9
    btn.Parent = TabBar

    local page = Instance.new("ScrollingFrame")
    page.Name = name
    page.Size = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = m.ScrollThickness
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.ScrollingDirection = Enum.ScrollingDirection.Y
    page.Visible = (order == 1)
    page.Parent = Content

    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, m.Padding)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Parent = page

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 4)
    pad.PaddingBottom = UDim.new(0, 12)
    pad.PaddingLeft = UDim.new(0, 2)
    pad.PaddingRight = UDim.new(0, 6)
    pad.Parent = page

    Pages[name], Tabs[name] = page, btn
    table.insert(UIRefs.TabButtons, btn)
    table.insert(UIRefs.Pages, { Page = page, List = list })

    BindHoverEffect(btn, function()
        return (ActiveTabName == name) and ToColor3(CONFIG.COLORS.UI_ACCENT) or Color3.fromRGB(30, 34, 42)
    end)

    Track(btn.MouseButton1Click:Connect(function()
        ActiveTabName = name
        for k, p in pairs(Pages) do
            p.Visible = (k == name)
            Tabs[k].BackgroundColor3 = (k == name) and ToColor3(CONFIG.COLORS.UI_ACCENT) or Color3.fromRGB(30, 34, 42)
        end
        if metrics().UseDrawer and SetDrawerState then
            SetDrawerState(false)
        end
    end))

    if order == 1 then
        ActiveTabName = name
        btn.BackgroundColor3 = ToColor3(CONFIG.COLORS.UI_ACCENT)
    end
    return page
end
local AddTab = MakeTab

local function AddToggle(page, text, get, set)
    local m = metrics()
    local baseColor = Color3.fromRGB(28, 32, 40)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, -4, 0, m.RowHeight)
    row.BackgroundColor3 = baseColor
    row.BorderSizePixel = 0
    row.AutoButtonColor = false
    row.Text = ""
    row.Parent = page
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 4); c.Parent = row

    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -68, 1, 0)
    l.Position = UDim2.fromOffset(10, 0)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.RobotoMono
    l.TextSize = m.FontSize
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextColor3 = ToColor3(CONFIG.COLORS.UI_TEXT)
    l.TextTruncate = Enum.TextTruncate.AtEnd
    l.Text = text
    l.Parent = row

    local pillW = m.UseDrawer and 44 or 38
    local pillH = m.UseDrawer and 22 or 18
    local st = Instance.new("Frame")
    st.Size = UDim2.fromOffset(pillW, pillH)
    st.Position = UDim2.new(1, -(pillW + 10), 0.5, -math.floor(pillH * 0.5))
    st.BorderSizePixel = 0
    st.BackgroundColor3 = get() and ToColor3(CONFIG.COLORS.UI_ACCENT) or Color3.fromRGB(55, 60, 70)
    st.Parent = row
    local sc = Instance.new("UICorner")
    sc.CornerRadius = UDim.new(0, 4); sc.Parent = st

    local function refresh(animate)
        local targetCol = get() and ToColor3(CONFIG.COLORS.UI_ACCENT) or Color3.fromRGB(55, 60, 70)
        if animate then
            TweenService:Create(st, TweenInfo.new(0.12), { BackgroundColor3 = targetCol }):Play()
        else
            st.BackgroundColor3 = targetCol
        end
    end

    BindHoverEffect(row, function() return baseColor end)
    Track(row.MouseButton1Click:Connect(function()
        set(not get()); refresh(true)
    end))
    refresh(false)
    table.insert(UIRefs.Refresh, function() refresh(false) end)
    table.insert(UIRefs.Rows, { Frame = row, Label = l, Pill = st })
    return row
end

local function AddCycle(page, text, options, get, set)
    local m = metrics()
    local baseColor = Color3.fromRGB(28, 32, 40)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, -4, 0, m.RowHeight)
    row.BackgroundColor3 = baseColor
    row.BorderSizePixel = 0
    row.AutoButtonColor = false
    row.Font = Enum.Font.RobotoMono
    row.TextSize = m.FontSize
    row.TextColor3 = ToColor3(CONFIG.COLORS.UI_TEXT)
    row.TextXAlignment = Enum.TextXAlignment.Left
    row.Parent = page
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 4); c.Parent = row

    local function refresh()
        row.Text = "  " .. text .. ": [" .. tostring(get()) .. "]"
    end

    BindHoverEffect(row, function() return baseColor end)
    Track(row.MouseButton1Click:Connect(function()
        local cur = table.find(options, get()) or 1
        set(options[(cur % #options) + 1]); refresh()
    end))
    refresh()
    table.insert(UIRefs.Refresh, refresh)
    table.insert(UIRefs.Rows, { Frame = row, Label = row })
    return row
end

local function AddButton(page, text, cb)
    local m = metrics()
    local baseColor = Color3.fromRGB(38, 48, 66)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -4, 0, m.ButtonHeight)
    b.BackgroundColor3 = baseColor
    b.BorderSizePixel = 0
    b.AutoButtonColor = false
    b.Font = Enum.Font.RobotoMono
    b.TextSize = m.FontSize
    b.TextColor3 = ToColor3(CONFIG.COLORS.UI_TEXT)
    b.Text = text
    b.Parent = page
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 4); c.Parent = b

    BindHoverEffect(b, function() return baseColor end)
    Track(b.MouseButton1Click:Connect(cb))
    table.insert(UIRefs.Buttons, b)
    return b
end

local function AddSlider(page, text, min, max, step, get, set)
    local m = metrics()
    local baseColor = Color3.fromRGB(28, 32, 40)
    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, -4, 0, m.SliderHeight)
    container.BackgroundColor3 = baseColor
    container.BorderSizePixel = 0
    container.Parent = page
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 4); c.Parent = container

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(0.68, -10, 0, 20)
    titleLbl.Position = UDim2.fromOffset(10, 4)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Font = Enum.Font.RobotoMono
    titleLbl.TextSize = m.FontSize
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.TextColor3 = ToColor3(CONFIG.COLORS.UI_TEXT)
    titleLbl.Text = text
    titleLbl.Parent = container

    local valLbl = Instance.new("TextLabel")
    valLbl.Size = UDim2.new(0.32, -10, 0, 20)
    valLbl.Position = UDim2.new(0.68, 0, 0, 4)
    valLbl.BackgroundTransparency = 1
    valLbl.Font = Enum.Font.RobotoMono
    valLbl.TextSize = m.FontSize
    valLbl.TextXAlignment = Enum.TextXAlignment.Right
    valLbl.TextColor3 = ToColor3(CONFIG.COLORS.UI_ACCENT)
    valLbl.Parent = container

    local hitBox = Instance.new("TextButton")
    hitBox.Size = UDim2.new(1, -20, 0, math.max(m.TapMin, m.SliderHeight - 22))
    hitBox.Position = UDim2.fromOffset(10, 22)
    hitBox.BackgroundTransparency = 1
    hitBox.Text = ""
    hitBox.AutoButtonColor = false
    hitBox.Parent = container

    local barBg = Instance.new("Frame")
    barBg.Size = UDim2.new(1, 0, 0, 4)
    barBg.Position = UDim2.new(0, 0, 0.5, -2)
    barBg.BackgroundColor3 = Color3.fromRGB(50, 56, 68)
    barBg.BorderSizePixel = 0
    barBg.Parent = hitBox
    local bc = Instance.new("UICorner")
    bc.CornerRadius = UDim.new(0, 2); bc.Parent = barBg

    local barFill = Instance.new("Frame")
    barFill.Size = UDim2.new(0, 0, 1, 0)
    barFill.BackgroundColor3 = ToColor3(CONFIG.COLORS.UI_ACCENT)
    barFill.BorderSizePixel = 0
    barFill.Parent = barBg
    local fc = Instance.new("UICorner")
    fc.CornerRadius = UDim.new(0, 2); fc.Parent = barFill

    local function Quantize(v)
        local clamped = math.clamp(v, min, max)
        if step and step > 0 then
            clamped = math.floor((clamped - min) / step + 0.5) * step + min
            clamped = math.clamp(clamped, min, max)
        end
        return tonumber(string.format("%.2f", clamped)) or clamped
    end

    local function refresh()
        local cur = math.clamp(tonumber(get()) or min, min, max)
        local alpha = (max > min) and ((cur - min) / (max - min)) or 0
        barFill.Size = UDim2.new(math.clamp(alpha, 0, 1), 0, 1, 0)
        if step and step < 1 then
            valLbl.Text = string.format("%.2f", cur)
        else
            valLbl.Text = tostring(math.floor(cur + 0.5))
        end
    end

    local sliding = false
    local function UpdateFromInput(inputPos)
        local absPos = barBg.AbsolutePosition.X
        local absWidth = math.max(barBg.AbsoluteSize.X, 1)
        local ratio = math.clamp((inputPos.X - absPos) / absWidth, 0, 1)
        set(Quantize(min + (max - min) * ratio))
        refresh()
    end

    Track(hitBox.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            sliding = true; UpdateFromInput(input.Position)
        end
    end))
    Track(UserInputService.InputChanged:Connect(function(input)
        if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            UpdateFromInput(input.Position)
        end
    end))
    Track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            sliding = false
        end
    end))

    BindHoverEffect(container, function() return baseColor end)
    refresh()
    table.insert(UIRefs.Refresh, refresh)
    table.insert(UIRefs.Sliders, { Container = container, Title = titleLbl, Value = valLbl, HitBox = hitBox })
    return container
end

local function AddInput(page, text, get, set, validate)
    local m = metrics()
    local baseColor = Color3.fromRGB(28, 32, 40)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -4, 0, m.InputHeight)
    row.BackgroundColor3 = baseColor
    row.BorderSizePixel = 0
    row.Parent = page
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 4); c.Parent = row

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.42, -10, 1, 0)
    lbl.Position = UDim2.fromOffset(10, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.RobotoMono
    lbl.TextSize = m.FontSize
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextColor3 = ToColor3(CONFIG.COLORS.UI_TEXT)
    lbl.TextTruncate = Enum.TextTruncate.AtEnd
    lbl.Text = text
    lbl.Parent = row

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(0.58, -12, 1, -8)
    box.Position = UDim2.new(0.42, 4, 0, 4)
    box.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
    box.BorderSizePixel = 0
    box.ClearTextOnFocus = false
    box.Font = Enum.Font.RobotoMono
    box.TextSize = m.FontSize
    box.TextColor3 = ToColor3(CONFIG.COLORS.UI_TEXT)
    box.PlaceholderColor3 = Color3.fromRGB(120, 128, 140)
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.Text = tostring(get() or "")
    box.Parent = row

    local bc = Instance.new("UICorner")
    bc.CornerRadius = UDim.new(0, 3); bc.Parent = box
    local bpad = Instance.new("UIPadding")
    bpad.PaddingLeft = UDim.new(0, 6); bpad.PaddingRight = UDim.new(0, 6); bpad.Parent = box
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(50, 58, 72); stroke.Thickness = 1; stroke.Parent = box

    local function refresh() box.Text = tostring(get() or "") end

    Track(box.FocusLost:Connect(function()
        local raw = box.Text
        if type(validate) == "function" then
            local ok, parsed = validate(raw)
            if ok then
                set(parsed)
                stroke.Color = ToColor3(CONFIG.COLORS.UI_ACCENT)
                task.delay(0.35, function()
                    if stroke and stroke.Parent then stroke.Color = Color3.fromRGB(50, 58, 72) end
                end)
            else
                stroke.Color = Color3.fromRGB(255, 75, 75)
                AddToast("Invalid input for " .. text, 2.0)
                task.delay(0.45, function()
                    if stroke and stroke.Parent then stroke.Color = Color3.fromRGB(50, 58, 72) end
                end)
            end
        else
            set(raw)
        end
        refresh()
    end))

    refresh()
    table.insert(UIRefs.Refresh, refresh)
    table.insert(UIRefs.Inputs, { Row = row, Label = lbl, Box = box })
    return row
end

-- === TABS ===
local TabFarm       = MakeTab("1. FARM", 1)
local TabCollect    = MakeTab("2. COLLECT", 2)
local TabVisuals    = MakeTab("3. VISUALS", 3)
local TabTuning     = MakeTab("4. TUNING", 4)
local TabProjection = MakeTab("5. PROJECTION", 5)
local TabConfig     = MakeTab("6. CONFIG", 6)

AddToggle(TabFarm, "Master Switch", function() return CONFIG.STATE.MasterEnable end, function(v)
    CONFIG.STATE.MasterEnable = v
    AddToast("Master Switch: " .. (v and "ON" or "OFF"), 1.6)
end)
AddToggle(TabFarm, "Teleport To Island", function() return CONFIG.STATE.TeleportToIsland end, function(v) CONFIG.STATE.TeleportToIsland = v end)
AddToggle(TabFarm, "Auto Quest Farm", function() return CONFIG.STATE.AutoQuestFarm end, function(v) CONFIG.STATE.AutoQuestFarm = v end)
AddToggle(TabFarm, "Auto Farm Nearest", function() return CONFIG.STATE.AutoFarmNearest end, function(v) CONFIG.STATE.AutoFarmNearest = v end)
AddToggle(TabFarm, "Auto Farm Bosses", function() return CONFIG.STATE.AutoFarmBosses end, function(v) CONFIG.STATE.AutoFarmBosses = v end)
AddToggle(TabFarm, "Auto Equip Weapon", function() return CONFIG.STATE.AutoEquipWeapon end, function(v) CONFIG.STATE.AutoEquipWeapon = v end)
AddToggle(TabFarm, "Auto Buso Haki", function() return CONFIG.STATE.AutoBusoHaki end, function(v) CONFIG.STATE.AutoBusoHaki = v end)
AddToggle(TabFarm, "Fast Attack", function() return CONFIG.STATE.FastAttack end, function(v) CONFIG.STATE.FastAttack = v end)

AddToggle(TabCollect, "Auto Collect Fruits", function() return CONFIG.STATE.AutoCollectFruits end, function(v) CONFIG.STATE.AutoCollectFruits = v end)
AddToggle(TabCollect, "Auto Collect Chests", function() return CONFIG.STATE.AutoCollectChests end, function(v) CONFIG.STATE.AutoCollectChests = v end)
AddButton(TabCollect, "Refresh Now (Rescan Collectibles)", function()
    RefreshCollectibles()
    AddToast(string.format("Fruits: %d | Chests: %d", #Runtime.FruitCache, #Runtime.ChestCache), 2.0)
end)
do
    local m = metrics()
    local counterRow = Instance.new("Frame")
    counterRow.Size = UDim2.new(1, -4, 0, m.RowHeight)
    counterRow.BackgroundColor3 = Color3.fromRGB(22, 25, 32)
    counterRow.BorderSizePixel = 0
    counterRow.Parent = TabCollect
    local cc = Instance.new("UICorner")
    cc.CornerRadius = UDim.new(0, 4); cc.Parent = counterRow
    local counterLbl = Instance.new("TextLabel")
    counterLbl.Size = UDim2.new(1, -12, 1, 0)
    counterLbl.Position = UDim2.fromOffset(6, 0)
    counterLbl.BackgroundTransparency = 1
    counterLbl.Font = Enum.Font.RobotoMono
    counterLbl.TextSize = m.FontSize
    counterLbl.TextXAlignment = Enum.TextXAlignment.Left
    counterLbl.TextColor3 = ToColor3(CONFIG.COLORS.UI_ACCENT)
    counterLbl.Parent = counterRow
    Runtime.CounterLabel = counterLbl
    table.insert(UIRefs.Rows, { Frame = counterRow, Label = counterLbl })
    UpdateCollectCounterUI()
end

AddToggle(TabVisuals, "Enemy ESP", function() return CONFIG.STATE.EspEnemies end, function(v) CONFIG.STATE.EspEnemies = v end)
AddToggle(TabVisuals, "Player ESP", function() return CONFIG.STATE.EspPlayers end, function(v) CONFIG.STATE.EspPlayers = v end)
AddToggle(TabVisuals, "Fruit ESP", function() return CONFIG.STATE.EspFruits end, function(v) CONFIG.STATE.EspFruits = v end)
AddToggle(TabVisuals, "Chest ESP", function() return CONFIG.STATE.EspChests end, function(v) CONFIG.STATE.EspChests = v end)
AddToggle(TabVisuals, "Draw Boxes", function() return CONFIG.STATE.DrawBoxes end, function(v) CONFIG.STATE.DrawBoxes = v end)
AddToggle(TabVisuals, "Draw Tracers", function() return CONFIG.STATE.DrawTracers end, function(v) CONFIG.STATE.DrawTracers = v end)
AddToggle(TabVisuals, "Draw Labels", function() return CONFIG.STATE.DrawLabels end, function(v) CONFIG.STATE.DrawLabels = v end)
AddToggle(TabVisuals, "Draw Health Bar", function() return CONFIG.STATE.DrawHealthBar end, function(v) CONFIG.STATE.DrawHealthBar = v end)

AddCycle(TabTuning, "Weapon", { "Melee", "Sword", "Blox Fruit" }, function() return CONFIG.STATE.SelectedWeaponType end, function(v)
    CONFIG.STATE.SelectedWeaponType = v
end)
local islands = { "None", "Starter Island", "Jungle", "Marine Fortress", "Sky Island", "Cafe (Sea 2)", "Kingdom of Rose", "Green Zone", "Mansion (Sea 3)", "Castle on the Sea" }
AddCycle(TabTuning, "Island", islands, function() return CONFIG.STATE.SelectedIsland end, function(v)
    CONFIG.STATE.SelectedIsland = v
    for _, r in ipairs(UIRefs.Refresh) do r() end
end)

AddSlider(TabTuning, "Hover Offset (Studs)", 4, 40, 1, function() return CONFIG.STATE.FarmDistanceOffset end, function(v)
    CONFIG.STATE.FarmDistanceOffset = v
end)
AddSlider(TabTuning, "Fly Speed (MoveSpeed)", 100, 360, 5, function() return CONFIG.STATE.MoveSpeed end, function(v)
    CONFIG.STATE.MoveSpeed = v
end)
AddSlider(TabTuning, "Farm Range (Studs)", 100, 5000, 50, function() return CONFIG.FARM_RANGE end, function(v)
    CONFIG.FARM_RANGE = v
end)
AddSlider(TabTuning, "Walk Speed", 16, 120, 2, function() return CONFIG.WALK_SPEED end, function(v)
    CONFIG.WALK_SPEED = v
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then pcall(function() hum.WalkSpeed = v end) end
end)
AddSlider(TabTuning, "ESP Dist (Studs)", 250, 10000, 250, function() return CONFIG.MAX_RENDER_DISTANCE end, function(v)
    CONFIG.MAX_RENDER_DISTANCE = v
end)

AddInput(TabTuning, "QuestName",
    function()
        local q = ActiveQuestEntry(); return q and q.QuestName or ""
    end,
    function(val)
        local q = ActiveQuestEntry(); if q then q.QuestName = val end
    end,
    function(raw)
        local trimmed = string.match(raw or "", "^%s*(.-)%s*$")
        if trimmed and #trimmed > 0 then return true, trimmed end
        return false, nil
    end
)

AddInput(TabTuning, "NpcPos (X,Y,Z)",
    function()
        local q = ActiveQuestEntry(); return q and FormatVec3(q.NpcPos) or "0,0,0"
    end,
    function(vec)
        local q = ActiveQuestEntry(); if q then q.NpcPos = vec end
    end,
    function(raw)
        local v = ParseVec3(raw); if v then return true, v end
        return false, nil
    end
)

AddInput(TabTuning, "FarmRange",
    function() return tostring(math.floor(CONFIG.FARM_RANGE)) end,
    function(val)
        CONFIG.FARM_RANGE = val
        for _, r in ipairs(UIRefs.Refresh) do r() end
    end,
    function(raw)
        local n = tonumber(raw)
        if n and n >= 50 and n <= 20000 then return true, n end
        return false, nil
    end
)

AddToggle(TabProjection, "Corner Box Style", function() return CONFIG.CORNER_BOX_STYLE end, function(v) CONFIG.CORNER_BOX_STYLE = v end)
AddToggle(TabProjection, "Clamp Tracers", function() return CONFIG.CLAMP_TRACERS end, function(v) CONFIG.CLAMP_TRACERS = v end)
AddToggle(TabProjection, "Draw FOV Ring", function() return CONFIG.DRAW_FOV_CIRCLE end, function(v) CONFIG.DRAW_FOV_CIRCLE = v end)
AddSlider(TabProjection, "FOV Radius (px)", 40, 400, 5, function() return CONFIG.FOV_RADIUS end, function(v)
    CONFIG.FOV_RADIUS = v
end)
AddSlider(TabProjection, "Max Depth (Studs)", 500, 10000, 250, function() return CONFIG.MAX_RENDER_DISTANCE end, function(v)
    CONFIG.MAX_RENDER_DISTANCE = v
end)

local ApplyPlatformLayout
local Teardown

AddCycle(TabConfig, "Platform Mode", { "auto", "pc", "tablet", "mobile" }, function() return CONFIG.PlatformSensitive end, function(v)
    CONFIG.PlatformSensitive = v
    Runtime.Platform = (v == "auto") and detectedPlatform or v
    ApplyPlatformLayout(RootGui, Main)
    AddToast("Layout: " .. string.upper(Runtime.Platform), 1.8)
end)
AddButton(TabConfig, "Save JSON", SaveConfig)
AddButton(TabConfig, "Load JSON", function()
    if LoadConfig() then
        ApplyPlatformLayout(RootGui, Main)
        for _, r in ipairs(UIRefs.Refresh) do r() end
    end
end)
AddButton(TabConfig, "Stop Flight", function()
    StopFlight(); AddToast("Flight stopped", 1.5)
end)
AddButton(TabConfig, "Unload Script", function()
    if Teardown then Teardown() end
end)

-- === PLATFORM LAYOUT ===
ApplyPlatformLayout = function(rootGui, main)
    if not rootGui or not main then return end

    -- FIX v6: re-read TopInset when forcing mobile on a device that started as PC
    if Runtime.Platform == "mobile" and (Runtime.TopInset or 0) == 0 then
        local ti = 0
        pcall(function() ti = GuiService:GetGuiInset().Y end)
        Runtime.TopInset = ti
    end

    local m = metrics()
    main.Size = m.WindowSize
    main.Position = m.WindowPos
    Header.Size = UDim2.new(1, 0, 0, m.HeaderHeight)

    if m.UseDrawer then
        DrawerButton.Visible = true
        DrawerButton.Size = UDim2.fromOffset(44, m.HeaderHeight - 4)
        DrawerButton.Position = UDim2.fromOffset(4, 2)
        LockBadge.Position = UDim2.fromOffset(52, 0)
        LockBadge.Size = UDim2.fromOffset(28, m.HeaderHeight)
        LockBadge.TextSize = m.HeaderFontSize
        Title.Position = UDim2.fromOffset(82, 0)
        Title.Size = UDim2.new(1, -90, 1, 0)
        Title.TextSize = m.HeaderFontSize

        DrawerBackdrop.Size = UDim2.new(1, 0, 1, -m.HeaderHeight)
        DrawerBackdrop.Position = UDim2.fromOffset(0, m.HeaderHeight)

        TabBar.Size = UDim2.new(0, m.SidebarWidth, 1, -m.HeaderHeight)
        if Runtime.DrawerOpen then
            TabBar.Position = UDim2.fromOffset(0, m.HeaderHeight)
            DrawerBackdrop.Visible = true
            DrawerBackdrop.BackgroundTransparency = 0.45
        else
            TabBar.Position = UDim2.fromOffset(-m.SidebarWidth - 10, m.HeaderHeight)
            DrawerBackdrop.Visible = false
            DrawerBackdrop.BackgroundTransparency = 1
        end

        Content.Size = UDim2.new(1, -16, 1, -(m.HeaderHeight + 10))
        Content.Position = UDim2.fromOffset(8, m.HeaderHeight + 5)
    else
        Runtime.DrawerOpen = false
        DrawerButton.Visible = false
        DrawerBackdrop.Visible = false

        LockBadge.Position = UDim2.fromOffset(10, 0)
        LockBadge.Size = UDim2.fromOffset(28, m.HeaderHeight)
        LockBadge.TextSize = m.HeaderFontSize
        Title.Position = UDim2.fromOffset(40, 0)
        Title.Size = UDim2.new(1, -48, 1, 0)
        Title.TextSize = m.HeaderFontSize

        TabBar.Size = UDim2.new(0, m.SidebarWidth, 1, -m.HeaderHeight)
        TabBar.Position = UDim2.fromOffset(0, m.HeaderHeight)

        Content.Size = UDim2.new(1, -(m.SidebarWidth + 12), 1, -(m.HeaderHeight + 10))
        Content.Position = UDim2.fromOffset(m.SidebarWidth + 6, m.HeaderHeight + 5)
    end

    -- FIX v6: compact title on mobile (fits 320px)
    if Runtime.Platform == "mobile" then
        Title.Text = "DRAGON v6 [=]"
    else
        Title.Text = string.format(
            "DRAGON v6 [%s/%s] [RShift: UI | End: Exit]",
            string.upper(Runtime.Platform),
            string.upper(Runtime.SubPlatform)
        )
    end

    for _, tBtn in ipairs(UIRefs.TabButtons) do
        tBtn.Size = UDim2.new(1, 0, 0, m.TabButtonHeight)
        tBtn.TextSize = m.FontSize
    end
    for _, pInfo in ipairs(UIRefs.Pages) do
        pInfo.Page.ScrollBarThickness = m.ScrollThickness
        pInfo.List.Padding = UDim.new(0, m.Padding)
    end
    for _, rInfo in ipairs(UIRefs.Rows) do
        rInfo.Frame.Size = UDim2.new(1, -4, 0, m.RowHeight)
        if rInfo.Label then rInfo.Label.TextSize = m.FontSize end
        if rInfo.Pill then
            local pillW = m.UseDrawer and 44 or 38
            local pillH = m.UseDrawer and 22 or 18
            rInfo.Pill.Size = UDim2.fromOffset(pillW, pillH)
            rInfo.Pill.Position = UDim2.new(1, -(pillW + 10), 0.5, -math.floor(pillH * 0.5))
        end
    end
    for _, b in ipairs(UIRefs.Buttons) do
        b.Size = UDim2.new(1, -4, 0, m.ButtonHeight)
        b.TextSize = m.FontSize
    end
    for _, sInfo in ipairs(UIRefs.Sliders) do
        sInfo.Container.Size = UDim2.new(1, -4, 0, m.SliderHeight)
        sInfo.Title.TextSize = m.FontSize
        sInfo.Value.TextSize = m.FontSize
        sInfo.HitBox.Size = UDim2.new(1, -20, 0, math.max(m.TapMin, m.SliderHeight - 22))
    end
    for _, iInfo in ipairs(UIRefs.Inputs) do
        iInfo.Row.Size = UDim2.new(1, -4, 0, m.InputHeight)
        iInfo.Label.TextSize = m.FontSize
        iInfo.Box.TextSize = m.FontSize
    end
end

CONFIG.STATE.MasterEnable = CONFIG.ENABLED_ON_LAUNCH
ApplyPlatformLayout(RootGui, Main)
for _, r in ipairs(UIRefs.Refresh) do r() end

-- === RENDER ===
local function OnRender()
    if not Runtime.Active then return end
    if not Runtime.FirstFrameVerified then Runtime.FirstFrameVerified = true; return end
    ResetPool()
    if not CONFIG.STATE.MasterEnable then return end
    local cam = workspace.CurrentCamera
    if not cam then return end
    local vp = cam.ViewportSize
    local center = Vector2.new(vp.X * 0.5, vp.Y * 0.5)
    local bottom = Vector2.new(vp.X * 0.5, vp.Y - 10)

    if CONFIG.DRAW_FOV_CIRCLE then
        DrawCircle(center, CONFIG.FOV_RADIUS, CONFIG.FOV_SEGMENTS, CONFIG.COLORS.FOV_RING)
    end

    if CONFIG.STATE.EspEnemies then
        local folder = workspace:FindFirstChild(TARGET.ENEMIES_FOLDER)
        if folder then
            for _, mob in ipairs(folder:GetChildren()) do
                local hrp, hum = GetRoot(mob)
                if hrp and hum and hum.Health > 0 then
                    local box = GetBox(hrp, 5.5)
                    if box and box.Distance <= CONFIG.MAX_RENDER_DISTANCE then
                        local isBoss = hum.MaxHealth >= 50000
                        local col = isBoss and CONFIG.COLORS.BOSS or CONFIG.COLORS.ENEMY
                        local hp = hum.Health / math.max(hum.MaxHealth, 1)
                        if CONFIG.STATE.DrawBoxes then DrawBox(box, col, hp) end
                        if CONFIG.STATE.DrawTracers then DrawTracer(bottom, box.CenterBottom, col) end
                        if CONFIG.STATE.DrawLabels then
                            DrawLabel(box.CenterBottom,
                                string.format("%s [%dm] %d%%", mob.Name, math.floor(box.Distance), math.floor(hp * 100)),
                                box.Distance, col)
                        end
                    end
                end
            end
        end
    end

    if CONFIG.STATE.EspPlayers then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                local hrp, hum = GetRoot(plr.Character)
                if hrp and hum and hum.Health > 0 then
                    local box = GetBox(hrp, 5.5)
                    if box and box.Distance <= CONFIG.MAX_RENDER_DISTANCE then
                        local col = CONFIG.COLORS.PLAYER
                        local hp = hum.Health / math.max(hum.MaxHealth, 1)
                        if CONFIG.STATE.DrawBoxes then DrawBox(box, col, hp) end
                        if CONFIG.STATE.DrawTracers then DrawTracer(bottom, box.CenterBottom, col) end
                        if CONFIG.STATE.DrawLabels then
                            DrawLabel(box.CenterBottom,
                                string.format("%s [%dm]", plr.DisplayName or plr.Name, math.floor(box.Distance)),
                                box.Distance, col)
                        end
                    end
                end
            end
        end
    end

    if CONFIG.STATE.EspFruits or CONFIG.STATE.EspChests then
        local function drawCache(cache, col)
            for _, obj in ipairs(cache) do
                if obj and obj.Parent then
                    local part = obj:IsA("BasePart") and obj or obj:FindFirstChild("Handle") or obj.PrimaryPart
                    if part and part:IsA("BasePart") then
                        local sp, on, dist = WorldToScreen(part.Position)
                        if sp and dist <= CONFIG.MAX_RENDER_DISTANCE then
                            if CONFIG.STATE.DrawTracers then DrawTracer(bottom, sp, col) end
                            if CONFIG.STATE.DrawLabels and on then
                                DrawLabel(sp, string.format("%s [%dm]", obj.Name, math.floor(dist)), dist, col)
                            end
                        end
                    end
                end
            end
        end
        if CONFIG.STATE.EspFruits then drawCache(Runtime.FruitCache, CONFIG.COLORS.FRUIT) end
        if CONFIG.STATE.EspChests then drawCache(Runtime.ChestCache, CONFIG.COLORS.CHEST) end
    end
end

-- === LOGIC ===
local function OnHeartbeat(dt)
    if not Runtime.Active or not Runtime.FirstFrameVerified then return end
    if not CONFIG.STATE.MasterEnable then StopFlight(); return end

    TickFlight(dt)
    local tickBefore = Runtime.FlightTick

    local now = os.clock()
    if (now * 1000 - Runtime.LastLogic) < CONFIG.UPDATE_INTERVAL_MS then return end
    Runtime.LastLogic = now * 1000

    local char = LocalPlayer.Character
    local hrp, hum = GetRoot(char)
    if not hrp or not hum or hum.Health <= 0 then StopFlight(); return end

    if CONFIG.WALK_SPEED and CONFIG.WALK_SPEED > 16 and not Runtime.FlightActive then
        pcall(function() hum.WalkSpeed = CONFIG.WALK_SPEED end)
    end

    if CONFIG.STATE.TeleportToIsland then
        local pos = TARGET.ISLANDS[CONFIG.STATE.SelectedIsland]
        if pos then
            SetFlight(CFrame.new(pos)); return
        end
    end

    local questInfo = TARGET.QUESTS[CONFIG.STATE.SelectedIsland]
    if CONFIG.STATE.AutoQuestFarm and questInfo then
        local visible = GetQuestVisible()
        if not visible then
            if questInfo.NpcPos then
                local distToNpc = (hrp.Position - questInfo.NpcPos).Magnitude
                if distToNpc > CONFIG.NPC_INTERACT_RADIUS then
                    SetFlight(CFrame.new(questInfo.NpcPos))
                else
                    SetFlight(CFrame.new(questInfo.NpcPos))
                    FireQuestStart(questInfo)
                end
            else
                StopFlight()
            end
            return
        end

        local mob = FindBestEnemy(false, questInfo.MobName)
        if mob then
            local mHrp = mob:FindFirstChild("HumanoidRootPart")
            if mHrp then
                if CONFIG.STATE.AutoEquipWeapon then EquipWeapon(CONFIG.STATE.SelectedWeaponType) end
                if CONFIG.STATE.AutoBusoHaki then TryBuso() end
                local hover = mHrp.Position + Vector3.new(0, CONFIG.STATE.FarmDistanceOffset, 0)
                SetFlight(CFrame.new(hover, mHrp.Position))
                if CONFIG.STATE.FastAttack then FastAttack() end
                return
            end
        end

        if questInfo.NpcPos then
            local waitHover = questInfo.NpcPos + Vector3.new(0, CONFIG.STATE.FarmDistanceOffset, 0)
            SetFlight(CFrame.new(waitHover))
        else
            StopFlight()
        end
        return
    end

    if CONFIG.STATE.AutoCollectFruits then
        local p = GetCollectiblePos(Runtime.FruitCache, hrp)
        if p then SetFlight(p.CFrame); return end
    end
    if CONFIG.STATE.AutoCollectChests then
        local p = GetCollectiblePos(Runtime.ChestCache, hrp)
        if p then SetFlight(p.CFrame); return end
    end

    if CONFIG.STATE.AutoFarmNearest or CONFIG.STATE.AutoFarmBosses then
        local mob
        if CONFIG.STATE.AutoFarmBosses then
            mob = FindBestEnemy(true)
        end
        if not mob and CONFIG.STATE.AutoFarmNearest then
            mob = FindBestEnemy(false)
        end
        if mob then
            local mHrp = mob:FindFirstChild("HumanoidRootPart")
            if mHrp then
                if CONFIG.STATE.AutoEquipWeapon then EquipWeapon(CONFIG.STATE.SelectedWeaponType) end
                if CONFIG.STATE.AutoBusoHaki then TryBuso() end
                local hover = mHrp.Position + Vector3.new(0, CONFIG.STATE.FarmDistanceOffset, 0)
                SetFlight(CFrame.new(hover, mHrp.Position))
                if CONFIG.STATE.FastAttack then FastAttack() end
            end
        end
    end

    if Runtime.FlightTick == tickBefore then
        StopFlight()
    end
end

-- === TEARDOWN ===
Teardown = function()
    if not Runtime.Active then return end
    Runtime.Active = false

    if Runtime.BusoTask then pcall(function() task.cancel(Runtime.BusoTask) end); Runtime.BusoTask = nil end
    if Runtime.QuestTask then pcall(function() task.cancel(Runtime.QuestTask) end); Runtime.QuestTask = nil end

    StopFlight()

    for i = #Runtime.Connections, 1, -1 do
        local c = Runtime.Connections[i]
        if c and c.Connected then pcall(function() c:Disconnect() end) end
        Runtime.Connections[i] = nil
    end

    for _, l in ipairs(Runtime.LinePool) do pcall(function() l:Destroy() end) end
    for _, l in ipairs(Runtime.LabelPool) do pcall(function() l:Destroy() end) end
    Runtime.LinePool, Runtime.LabelPool = {}, {}
    Runtime.FruitCache, Runtime.ChestCache = {}, {}
    Runtime.HookedFolders = {}
    Runtime.PartsList = nil

    for k in pairs(CONFIG.STATE) do
        if type(CONFIG.STATE[k]) == "boolean" then CONFIG.STATE[k] = false end
    end

    if RootGui then pcall(function() RootGui:Destroy() end); RootGui = nil end
    if genv.DragonTeardown == Teardown then genv.DragonTeardown = nil end
    genv.ArgonTeardown = nil
end

Track(UserInputService.InputBegan:Connect(function(input, gp)
    if input.KeyCode == CONFIG.EXIT_KEY then
        Teardown()
    elseif input.KeyCode == CONFIG.TOGGLE_UI_KEY and not gp then
        if Main then Main.Visible = not Main.Visible end
    end
end))
Track(RunService.Stepped:Connect(EnforceNoClipStep))
Track(RunService.RenderStepped:Connect(OnRender))
Track(RunService.Heartbeat:Connect(OnHeartbeat))

RefreshCollectibles()
genv.ArgonTeardown = nil
genv.DragonTeardown = Teardown

-- ============================================================================
-- RUNTIME CHECKLIST (in-client verification, не тест):
-- 1. Инжект на пустом сервере с MasterEnable=OFF — Output чист, GUI видно.
-- 2. ESP по одному: Enemies → Players → Fruits → Chests, потом Draw Tracers.
-- 3. Сбор: Refresh Now → включить Auto Collect Fruits → собрать 1 фрукт.
-- 4. Фарм: Auto Farm Nearest + Hover Offset 14, 30 секунд, смотреть удары.
-- 5. Боссы: Auto Farm Bosses + Auto Farm Nearest одновременно — боссы первыми.
-- 6. Квест: Auto Quest Farm + Island Starter Island, подлёт к NPC, старт.
-- 7. FireQuestStart timeout: CommF_:Destroy() — через 5с новый StartQuest
--    проходит (не зависает).
-- 8. Mobile: Layout = mobile → drawer "[=]" открывается, тапы попадают в 44px.
-- 9. iOS: TopInset применяется, "[=]" и Title не под notch.
-- 10. End: Teardown → в CoreGui пусто, genv.DragonTeardown == nil.
-- ============================================================================
