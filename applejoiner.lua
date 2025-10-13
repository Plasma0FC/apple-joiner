
local Luminosity = {}

-- Services
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

-- Variáveis do jogador
local Char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local Hum = Char:WaitForChild("Humanoid")
local HRP = Char:WaitForChild("HumanoidRootPart")

-- Constantes
local SPEED = 35
local HIGH_JUMP = 100
local PlaceId = game.PlaceId

-- Estados das funções
local toggles = { 
    Speed = false, 
    HighJump = false, 
    Steal = false, 
    ["ESP Timer"] = false, 
    ["Tema Color"] = false, 
    ["Bases Transparência"] = false, 
    ["Shops Transparente"] = false, 
    ["Maquina Transparente"] = false, 
    ["Roleta Transparente"] = false, 
    ["Chão Transparente"] = false, 
    ["ESP Player"] = false, 
    ["ESP Name"] = false, 
    ["Remover Textos"] = false 
}

-- Cores customizáveis
local customColors = {
    temaRoxo = Color3.fromRGB(187, 113, 255),
    plotSign = Color3.fromRGB(148, 11, 1),
    chaoColor = Color3.fromRGB(106, 57, 9),
    -- ESP PLAYER: roxo com sublinhado (outline) vermelho
    espPlayer = Color3.fromRGB(187, 113, 255),
    espPlayerOutline = Color3.fromRGB(255, 0, 0),
    -- ESP SCRIPT (mesmo script): laranja com sublinhado (outline) vermelho
    espScript = Color3.fromRGB(255, 165, 0),
    espScriptOutline = Color3.fromRGB(255, 0, 0),
    espName = Color3.fromRGB(148, 11, 1),
    espTimer = Color3.fromRGB(148, 11, 1)
}

-- Variáveis globais
local boosted = false
local speedMultiplier = 1.65
local activeLockTimeEsp = false
local brainrotActive = false
local espscriptActive = false
local lteInstances = {}
local plotName = nil
local stealGui = nil

-- ===============================
-- AUTO-JOINER (WS + QUEUE + RANGES)
-- ===============================
-- Ranges
local enabledRanges = { micro = false, low = false, mid = false, high = false, ultra = false }

-- Queue
local pendingJobs = {}
local inQueue = {}
local processingJobs = false
local isAutoJoinRunning = false

local function enqueueJob(jobId)
    if not jobId or jobId == "" then return end
    if inQueue[jobId] then return end
    table.insert(pendingJobs, jobId)
    inQueue[jobId] = true
    warn("[APPLE-JOINER V2] Enqueued job:", jobId, "(queue size:", #pendingJobs .. ")")
end

local function takeLatestJob()
    if #pendingJobs == 0 then return nil end
    local jobId = pendingJobs[#pendingJobs]
    table.remove(pendingJobs, #pendingJobs)
    inQueue[jobId] = nil
    return jobId
end

local function hasNewJobs()
    return #pendingJobs > 0
end

-- Range selector
local function pickMatchingRange(value)
    if enabledRanges.micro and value >= 1_000_000 and value < 10_000_000 then return "micro" end
    if enabledRanges.low   and value >= 10_000_000 and value < 50_000_000 then return "low" end
    if enabledRanges.mid   and value >= 50_000_000 and value < 100_000_000 then return "mid" end
    if enabledRanges.high  and value >= 100_000_000 and value < 500_000_000 then return "high" end
    if enabledRanges.ultra and value >= 500_000_000 and value < 10_000_000_000 then return "ultra" end
    return nil
end

-- WebSocket setup
local WS_URL = "wss://applesite-production.up.railway.app/events"
local PRESENCE_URL = "https://applesite-production.up.railway.app/presence"
local wsProvider, connectFunction = nil, nil
if syn and syn.websocket and syn.websocket.connect then
    wsProvider = syn.websocket
    connectFunction = syn.websocket.connect
elseif WebSocket and WebSocket.connect then
    wsProvider = WebSocket
    connectFunction = WebSocket.connect
elseif syn and syn.websocket then
    wsProvider = syn.websocket
    connectFunction = syn.websocket.connect
elseif WebSocket then
    wsProvider = WebSocket
    connectFunction = WebSocket.connect
end

-- Join logic (retry until new job arrives)
local function joinServer(jobId)
    local attemptOk, requestErr = pcall(function()
        TeleportService:TeleportToPlaceInstance(PlaceId, jobId, LocalPlayer)
    end)
    if not attemptOk then
        warn("[APPLE-JOINER V2] Teleport request error:", tostring(requestErr))
        return false
    end

    -- Detectar falha explícita via TeleportInitFailed
    local result = nil
    local conFail
    conFail = TeleportService.TeleportInitFailed:Connect(function(player, teleportResult, errorMessage)
        if player ~= LocalPlayer then return end
        warn("[APPLE-JOINER V2] TeleportInitFailed:", tostring(teleportResult), tostring(errorMessage))
        result = false
    end)

    local startedAt = os.clock()
    while result == nil and (os.clock() - startedAt) < 6 do
        task.wait(0.2)
    end
    if conFail then pcall(function() conFail:Disconnect() end) end

    if result == false then
        warn("[APPLE-JOINER V2] Teleport failed, will retry")
        return false
    end

    -- Nunca assumir sucesso silencioso, continuar tentando
    warn("[APPLE-JOINER V2] No explicit failure; will retry this JobID")
    return false
end

local function startAutoJoin()
    if not connectFunction then
        warn("[APPLE-JOINER V2] WebSocket not available in this executor")
        return
    end
    local Http = HttpService
    local reconnectDelay = 1

    local function ensureProcessor()
        if processingJobs then return end
        processingJobs = true
        task.spawn(function()
            while isAutoJoinRunning do
                local jobId = takeLatestJob()
                if not jobId then
                    task.wait(0.2)
                else
                    while isAutoJoinRunning do
                        warn("[APPLE-JOINER V2] Processing job:", jobId, "attempt: continuous")
                        local ok = joinServer(jobId)
                        if ok then break end
                        if hasNewJobs() then
                            warn("[APPLE-JOINER V2] Newer job arrived, requeue current:", jobId)
                            enqueueJob(jobId)
                            break
                        end
                task.wait(0.2)
                    end
                end
            end
            processingJobs = false
        end)
    end

    local function connect()
        if not isAutoJoinRunning then return end
        local ok, socket = pcall(function()
            return connectFunction(WS_URL)
        end)
        if not ok or not socket then
            warn("[APPLE-JOINER V2] WS connect failed:", tostring(socket))
            task.wait(reconnectDelay)
            reconnectDelay = math.min(reconnectDelay * 2, 30)
            return connect()
        end
        reconnectDelay = 1
        warn("[APPLE-JOINER V2] WebSocket connected!")

        local function onMessage(msg)
            if not isAutoJoinRunning then return end
            local okMsg, data = pcall(function()
                return Http:JSONDecode(msg)
            end)
            if not okMsg or type(data) ~= "table" then return end
            if data.type == "event" and data.payload then
                local payload = data.payload
                local value = tonumber(payload.patchValue) or 0
                local jobId = payload.serverId
                local rangeKey = pickMatchingRange(value)
                if rangeKey and jobId then
                    enqueueJob(jobId)
                    ensureProcessor()
                end
            end
        end

        local function onClose()
            if not isAutoJoinRunning then return end
            warn("[APPLE-JOINER V2] WS closed, reconnecting...")
            task.wait(0.1)
            reconnectDelay = 0.1
            connect()
        end

        local function onError()
            if not isAutoJoinRunning then return end
            warn("[APPLE-JOINER V2] WS error, reconnecting...")
            task.wait(0.1)
            reconnectDelay = 0.1
            connect()
        end

        -- Bind handlers (compatível com :Connect ou callback)
        local function tryBind(eventField, handler)
            if not eventField then return false end
            local okb = false
            if (typeof(eventField) == "table" or typeof(eventField) == "userdata") and type(eventField.Connect) == "function" then
                okb = pcall(function() eventField:Connect(handler) end) == true
            elseif type(eventField) == "function" then
                okb = pcall(function() eventField(handler) end) == true
            end
            return okb
        end

        local boundMsg = tryBind(socket.OnMessage, onMessage)
        local _ = tryBind(socket.OnClose, onClose)
        local __ = tryBind(socket.OnError, onError)
        if not boundMsg then
            warn("[APPLE-JOINER V2] OnMessage not bound. Reconnecting...")
            task.wait(reconnectDelay)
            reconnectDelay = math.min(reconnectDelay * 2, 30)
            return connect()
        end

        ensureProcessor()
    end

    connect()
end

-- ===============================
-- DESCOBRIR PLOT DO JOGADOR
-- ===============================
do
    local success, result = pcall(function()
        for _, plot in pairs(workspace.Plots:GetChildren()) do
            if plot.Owner and plot.Owner.Value == LocalPlayer then
                plotName = plot.Name
                break
            end
        end
    end)
end

-- ===============================
-- SISTEMA DE SALVAR/CARREGAR CONFIGURAÇÕES
-- ===============================

-- Armazenar referências dos toggles para atualização visual
local toggleReferences = {}

-- Função para atualizar toggles visuais na GUI
local function updateToggleVisuals()
    for toggleName, isActive in pairs(toggles) do
        local toggleRef = toggleReferences[toggleName]
        if toggleRef and toggleRef.button then
            toggleRef.button.BackgroundColor3 = isActive and Color3.fromRGB(231, 231, 231) or Color3.fromRGB(30, 30, 30)
        end
    end
end

-- Função para salvar configurações
local function saveSettings()
    local settings = {
        toggles = toggles,
        customColors = customColors,
        enabledRanges = enabledRanges,
        autoJoinActive = autoJoinActive,
        -- Salvar configurações específicas
        speedMultiplier = speedMultiplier,
        boosted = boosted
    }
    
    local success, result = pcall(function()
        local json = game:GetService("HttpService"):JSONEncode(settings)
        writefile("apple_hub_settings.json", json)
    end)
    
    if success then
        print("✅ Configurações salvas com sucesso!")
        -- Mostrar notificação na tela
        local notification = Instance.new("ScreenGui")
        notification.Name = "SaveNotification"
        notification.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
        
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(0, 300, 0, 60)
        frame.Position = UDim2.new(0.5, -150, 0, 50)
        frame.BackgroundColor3 = Color3.fromRGB(0, 150, 0)
        frame.BorderSizePixel = 0
        frame.Parent = notification
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 10)
        corner.Parent = frame
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = "✅ Configurações Salvas!"
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.TextScaled = true
        label.Font = Enum.Font.GothamBold
        label.Parent = frame
        
        -- Remover notificação após 3 segundos
        task.wait(3)
        notification:Destroy()
    else
        print("❌ Erro ao salvar configurações: " .. tostring(result))
    end
end

-- Função para carregar configurações
local function loadSettings()
    local success, result = pcall(function()
        if readfile then
            local json = readfile("apple_hub_settings.json")
            return game:GetService("HttpService"):JSONDecode(json)
        end
        return nil
    end)
    
    if success and result then
        -- Aplicar configurações carregadas
        if result.toggles then
            for k, v in pairs(result.toggles) do
                toggles[k] = v
            end
        end
        
        if result.customColors then
            for k, v in pairs(result.customColors) do
                customColors[k] = v
            end
        end
        
        if result.enabledRanges then
            for k, v in pairs(result.enabledRanges) do
                enabledRanges[k] = v
            end
        end
        
        if result.autoJoinActive ~= nil then
            autoJoinActive = result.autoJoinActive
        end
        
        if result.speedMultiplier then
            speedMultiplier = result.speedMultiplier
        end
        
        if result.boosted ~= nil then
            boosted = result.boosted
        end
        
        print("✅ Configurações carregadas com sucesso!")
        return true
    else
        print("ℹ️ Nenhuma configuração salva encontrada ou erro ao carregar")
        return false
    end
end

-- ===============================
-- FUNÇÕES PRINCIPAIS
-- ===============================

-- Notificação personalizada
local function UltimateNotify(msg)
    print("🚀 ULTIMATE HUB: " .. (msg or "Função ativada com sucesso!"))
end

-- Função de ESP Timer
local function updatelock()
    if not activeLockTimeEsp then
        for _, instance in pairs(lteInstances) do
            if instance then instance:Destroy() end
        end
        lteInstances = {}
        return
    end

    for _, plot in pairs(workspace.Plots:GetChildren()) do
        local billboardName = "LockTimeESP_" .. plot.Name
        local timeLabel = plot:FindFirstChild("Purchases", true)
            and plot.Purchases:FindFirstChild("PlotBlock", true)
            and plot.Purchases.PlotBlock.Main:FindFirstChild("BillboardGui", true)
            and plot.Purchases.PlotBlock.Main.BillboardGui:FindFirstChild("RemainingTime", true)

        if timeLabel and timeLabel:IsA("TextLabel") then
            local existing = lteInstances[plot.Name]
            local isUnlocked = timeLabel.Text == "0s"
            local displayText = isUnlocked and "Unlocked" or ("Lock: " .. timeLabel.Text)

            local color = customColors.espTimer
            if plot.Name == plotName then
                color = Color3.fromRGB(80, 220, 80)
            elseif isUnlocked then
                color = Color3.fromRGB(255, 100, 100)
            end

            if not existing then
                local gui = Instance.new("BillboardGui")
                gui.Name = billboardName
                gui.Size = UDim2.new(0, 90, 0, 25)
                gui.StudsOffset = Vector3.new(0, 2.5, 0)
                gui.AlwaysOnTop = true
                gui.Adornee = plot.Purchases.PlotBlock.Main
                gui.Parent = plot

                local label = Instance.new("TextLabel")
                label.Size = UDim2.new(1, 0, 1, 0)
                label.BackgroundTransparency = 1
                label.TextScaled = true
                label.TextColor3 = color
                label.TextStrokeTransparency = 0
                label.TextStrokeColor3 = Color3.fromRGB(0,0,0)
                label.Font = Enum.Font.GothamBold
                label.Text = displayText
                label.Parent = gui

                lteInstances[plot.Name] = gui
            else
                local label = existing:FindFirstChildOfClass("TextLabel")
                if label then
                    label.Text = displayText
                    label.TextColor3 = color
                    label.Font = Enum.Font.GothamBold
                end
            end
        end
    end
end

-- Função para aplicar tema roxo
local function applyPurpleNeonTheme()
    local lighting = game:GetService("Lighting")
    
    local skyGalaxy = lighting:FindFirstChild("SkyGalaxy") or lighting:FindFirstChild("Sky")
    if not skyGalaxy then
        skyGalaxy = Instance.new("Sky")
        skyGalaxy.Parent = lighting
    end
    
    -- Configurar skybox roxo
    skyGalaxy.SkyboxBk = "http://www.roblox.com/asset/?id=570557620"
    skyGalaxy.SkyboxDn = "http://www.roblox.com/asset/?id=570557620"
    skyGalaxy.SkyboxFt = "http://www.roblox.com/asset/?id=570557620"
    skyGalaxy.SkyboxLf = "http://www.roblox.com/asset/?id=570557620"
    skyGalaxy.SkyboxRt = "http://www.roblox.com/asset/?id=570557620"
    skyGalaxy.SkyboxUp = "http://www.roblox.com/asset/?id=570557620"
    skyGalaxy.StarCount = 3000
    skyGalaxy.MoonTextureId = "http://www.roblox.com/asset/?id=1084891329"
    skyGalaxy.SunTextureId = "http://www.roblox.com/asset/?id=6196665106"
    
    local colorCorrection = lighting.ColorCCorrection
    colorCorrection.TintColor = Color3.fromRGB(255, 255, 255)
    
    local atmosphereGalaxy = lighting:FindFirstChild("AtmosphereGalaxy")
    if atmosphereGalaxy then
        atmosphereGalaxy.Color = customColors.temaRoxo
        local r, g, b = customColors.temaRoxo.R, customColors.temaRoxo.G, customColors.temaRoxo.B
        atmosphereGalaxy.Decay = Color3.fromRGB(r * 50, g * 20, b * 80)
        atmosphereGalaxy.Density = 0.4
    end
    
    local r, g, b = customColors.temaRoxo.R, customColors.temaRoxo.G, customColors.temaRoxo.B
    lighting.Ambient = Color3.fromRGB(r * 80, g * 50, b * 120)
    lighting.OutdoorAmbient = Color3.fromRGB(r * 70, g * 40, b * 100)
    lighting.Brightness = 3
    lighting.ColorShift_Bottom = Color3.fromRGB(r * 20, g * 10, b * 30)
    lighting.ColorShift_Top = Color3.fromRGB(r * 80, g * 50, b * 120)
    
    print("Tema roxo neon aplicado!")
end

-- Função para reverter tema
local function resetToDefaultTheme()
    local lighting = game:GetService("Lighting")
    local colorCorrection = lighting.ColorCCorrection
    colorCorrection.TintColor = Color3.fromRGB(255, 255, 255)
    
    lighting.Ambient = Color3.fromRGB(70, 70, 70)
    lighting.OutdoorAmbient = Color3.fromRGB(127, 127, 127)
    lighting.Brightness = 1
    lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
    lighting.ColorShift_Top = Color3.fromRGB(0, 0, 0)
    
    print("Tema padrão restaurado!")
end

-- Função para aplicar transparência nas bases
local function applyTransparency()
    repeat wait() until game:IsLoaded()
    local t = 0.7
    
    local function makeTransparent()
        task.wait(3)
        for i,v in pairs(workspace.Plots:GetDescendants()) do
            if v.Name == "structure base home" and (
                v.Size == Vector3.new(45, 16.999996185302734, 2) or
                v.Size == Vector3.new(45, 44.999996185302734, 2) or
                v.Size == Vector3.new(31, 10.999996185302734, 2) or
                v.Size == Vector3.new(3, 3, 15) or v.Size == Vector3.new(3, 3, 18) or
                v.Size == Vector3.new(1, 3, 11) or v.Size == Vector3.new(1, 29, 2) or
                v.Size == Vector3.new(1, 23, 1) or v.Size == Vector3.new(1, 1, 9) or
                v.Size == Vector3.new(1, 21, 9) or v.Size == Vector3.new(1, 37, 9) or
                v.Size == Vector3.new(1, 39, 1) or v.Size == Vector3.new(1, 45, 2)
            ) then
                v.Transparency = t
            elseif v.Name == "Decoration" and v.Parent.Name == "Decorations" then
                v.Transparency = t
                v.Parent.Part.Transparency = t
            elseif v.Name == "Main" and v.Parent.Name == "Claim" then
                v.Transparency = t
            elseif v.Name == "PlotSign" then
                v.Color = customColors.plotSign
            end
        end
        print("Transparência das bases aplicada!")
    end
    
    makeTransparent()
end

-- Função para reverter transparência das bases
local function resetTransparency()
    task.wait(1)
    for i,v in pairs(workspace.Plots:GetDescendants()) do
        if v.Name == "structure base home" then
            v.Transparency = 0
        elseif v.Name == "Decoration" and v.Parent.Name == "Decorations" then
            v.Transparency = 0
            v.Parent.Part.Transparency = 0
        elseif v.Name == "Main" and v.Parent.Name == "Claim" then
            v.Transparency = 0
        elseif v.Name == "PlotSign" then
            v.Color = Color3.fromRGB(163, 162, 165)
        end
    end
    print("Transparência das bases removida!")
end

-- Função base para transparência
local function setTransparencySafe(object, t)
    if object and object.Parent then
        if object:IsA("BasePart") then
            object.Transparency = t
        elseif object:IsA("ImageLabel") or object:IsA("ImageButton") then
            object.ImageTransparency = t
        elseif object:IsA("TextLabel") or object:IsA("TextButton") then
            local specialTexts = {"Countdown", "DisplayText", "Robux Shop", "Shop", "TextLabel"}
            local isSpecial = false
            for _, name in pairs(specialTexts) do
                if object.Name == name then isSpecial = true break end
            end
            if not isSpecial then
                object.BackgroundTransparency = t
            end
        end
    end
end

-- Shops transparente
local function applyShopsTransparency()
    local t = 0.7
    local function applyToAll(parent)
        if not parent then return end
        for _, obj in pairs(parent:GetDescendants()) do
            setTransparencySafe(obj, t)
        end
    end
    
    local shop = workspace:FindFirstChild("Shop")
    if shop then applyToAll(shop) end
    
    local robuxShop = workspace:FindFirstChild("RobuxShop")
    if robuxShop then applyToAll(robuxShop) end
    
    print("Shops transparentes!")
end

local function resetShopsTransparency()
    local function revertAll(parent)
        if not parent then return end
        for _, obj in pairs(parent:GetDescendants()) do
            setTransparencySafe(obj, 0)
        end
    end
    
    local shop = workspace:FindFirstChild("Shop")
    if shop then revertAll(shop) end
    
    local robuxShop = workspace:FindFirstChild("RobuxShop")
    if robuxShop then revertAll(robuxShop) end
    
    print("Shops opacas!")
end

-- Máquina transparente
local function applyMaquinaTransparency()
    local t = 0.7
    local function applyToAll(parent)
        if not parent then return end
        for _, obj in pairs(parent:GetDescendants()) do
            setTransparencySafe(obj, t)
        end
    end
    
    local machine = workspace:FindFirstChild("CraftingMachine")
    if machine then
        if machine:FindFirstChild("AnotherDecoration") then applyToAll(machine.AnotherDecoration) end
        if machine:FindFirstChild("CollectZone") then applyToAll(machine.CollectZone) end
        if machine:FindFirstChild("Craft") then applyToAll(machine.Craft) end
        if machine:FindFirstChild("CraftingMachine") then applyToAll(machine.CraftingMachine) end
    end
    
    print("Máquina transparente!")
end

local function resetMaquinaTransparency()
    local function revertAll(parent)
        if not parent then return end
        for _, obj in pairs(parent:GetDescendants()) do
            setTransparencySafe(obj, 0)
        end
    end
    
    local machine = workspace:FindFirstChild("CraftingMachine")
    if machine then
        if machine:FindFirstChild("AnotherDecoration") then revertAll(machine.AnotherDecoration) end
        if machine:FindFirstChild("CollectZone") then revertAll(machine.CollectZone) end
        if machine:FindFirstChild("Craft") then revertAll(machine.Craft) end
        if machine:FindFirstChild("CraftingMachine") then revertAll(machine.CraftingMachine) end
    end
    
    print("Máquina opaca!")
end

-- Roleta transparente
local function applyRoletaTransparency()
    local t = 0.7
    local wheels = workspace:FindFirstChild("GalaxySpinWheels")
    if wheels and wheels:FindFirstChild("1") then
        for _, obj in pairs(wheels["1"]:GetDescendants()) do
            setTransparencySafe(obj, t)
        end
    end
    print("Roleta transparente!")
end

local function resetRoletaTransparency()
    local wheels = workspace:FindFirstChild("GalaxySpinWheels")
    if wheels and wheels:FindFirstChild("1") then
        for _, obj in pairs(wheels["1"]:GetDescendants()) do
            setTransparencySafe(obj, 0)
        end
    end
    print("Roleta opaca!")
end

-- Chão transparente
local function applyChaoTransparency()
    local map = workspace:FindFirstChild("Map")
    if map then
        local ground = map:FindFirstChild("Ground")
        if ground then ground.Transparency = 1 end
        
        local carpet = map:FindFirstChild("Carpet")
        if carpet then carpet.Color = customColors.chaoColor end
    end
    print("Chão modificado!")
end

local function resetChaoTransparency()
    local map = workspace:FindFirstChild("Map")
    if map then
        local ground = map:FindFirstChild("Ground")
        if ground then ground.Transparency = 0 end
        
        local carpet = map:FindFirstChild("Carpet")
        if carpet then carpet.Color = Color3.fromRGB(106, 57, 9) end
    end
    print("Chão restaurado!")
end

-- ESP Player
local function applyESPPlayer()
    local players = game:GetService("Players")
    local function addESP(player)
        if player == LocalPlayer then return end
        local function createESP(character)
            if not character then return end
            if character:FindFirstChild("PlayerESP") then
                character.PlayerESP:Destroy()
            end
            
            local highlight = Instance.new("Highlight")
            highlight.Name = "PlayerESP"
            highlight.FillColor = customColors.espPlayer
            highlight.OutlineColor = customColors.espPlayerOutline
            highlight.FillTransparency = 0.3
            highlight.OutlineTransparency = 0
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.Adornee = character
            highlight.Parent = character
            -- Se existir ScriptESP nesse character, re-anexar para ficar por cima
            local scriptEsp = character:FindFirstChild("ScriptESP")
            if scriptEsp then
                local p = scriptEsp.Parent
                scriptEsp.Parent = nil
                scriptEsp.Parent = p
                -- Garantir que ScriptESP tenha prioridade máxima
                scriptEsp.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            end
        end
        
        if player.Character then createESP(player.Character) end
        player.CharacterAdded:Connect(createESP)
    end
    
    for _, player in pairs(players:GetPlayers()) do addESP(player) end
    players.PlayerAdded:Connect(addESP)
    print("ESP Player ativado!")
end

local function removeESPPlayer()
    for _, player in pairs(Players:GetPlayers()) do
        if player.Character then
            local esp = player.Character:FindFirstChild("PlayerESP")
            if esp then esp:Destroy() end
        end
    end
    print("ESP Player removido!")
end

-- ESP Name
local function applyESPName()
    local players = game:GetService("Players")
    local function addNameESP(player)
        if player == LocalPlayer then return end
        local function createNameESP(character)
            if not character then return end
            if character:FindFirstChild("NameESP") then
                character.NameESP:Destroy()
            end
            
            local billboardGui = Instance.new("BillboardGui")
            billboardGui.Name = "NameESP"
            billboardGui.Size = UDim2.new(0, 80, 0, 20)
            billboardGui.StudsOffset = Vector3.new(0, 2.5, 0)
            billboardGui.Adornee = character:FindFirstChild("Head")
            billboardGui.AlwaysOnTop = true
            billboardGui.MaxDistance = math.huge
            billboardGui.Parent = character
            
            local nameLabel = Instance.new("TextLabel")
            nameLabel.Size = UDim2.new(1, 0, 1, 0)
            nameLabel.BackgroundTransparency = 1
            nameLabel.Text = player.Name
            nameLabel.TextColor3 = customColors.espName
            nameLabel.TextStrokeTransparency = 0
            nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
            nameLabel.TextScaled = true
            nameLabel.Font = Enum.Font.GothamBold
            nameLabel.Parent = billboardGui
        end
        
        if player.Character then createNameESP(player.Character) end
        player.CharacterAdded:Connect(createNameESP)
    end
    
    for _, player in pairs(players:GetPlayers()) do addNameESP(player) end
    players.PlayerAdded:Connect(addNameESP)
    print("ESP Name ativado!")
end

-- Marcação de quem usa o mesmo script (handshake via Attribute)
local APPLE_SCRIPT_ATTR = "AppleHubUser"
pcall(function()
    if not LocalPlayer:GetAttribute(APPLE_SCRIPT_ATTR) then
        LocalPlayer:SetAttribute(APPLE_SCRIPT_ATTR, true)
    end
end)

-- forward-declare para permitir uso antes da definição
local httpRequestJson

local function applyESPScript()
    if espscriptActive then return end
    -- Ativa loop de presença no servidor AppleHub
    espscriptActive = true
    task.spawn(function()
        while espscriptActive do
            -- Enviar presença do local player
            local okAnnounce = httpRequestJson("POST", PRESENCE_URL .. "/announce", {
                userId = LocalPlayer.UserId,
                name = LocalPlayer.Name,
                placeId = PlaceId,
                jobId = game.JobId,
            })
            if okAnnounce then
                warn("[APPLE-JOINER V2] Presence announced: ", LocalPlayer.UserId, LocalPlayer.Name)
            else
                warn("[APPLE-JOINER V2] Presence announce failed")
            end
            -- Buscar lista de usuários AppleHub na mesma partida
            local ok, data = httpRequestJson("GET", PRESENCE_URL .. "/list?placeId=" .. tostring(PlaceId) .. "&jobId=" .. tostring(game.JobId))
            if ok and type(data) == "table" and type(data.users) == "table" then
                -- Construir set de userIds
                local isAppleUser = {}
                for _, u in ipairs(data.users) do
                    if u and u.userId then isAppleUser[tonumber(u.userId)] = true end
                end
                -- Aplicar/Remover highlight conforme presença
                for _, plr in pairs(Players:GetPlayers()) do
                    if plr ~= LocalPlayer and plr.Character then
                        local has = isAppleUser[plr.UserId] == true
                        local esp = plr.Character:FindFirstChild("ScriptESP")
                        if has and not esp then
                            local hl = Instance.new("Highlight")
                            hl.Name = "ScriptESP"
                            hl.FillColor = customColors.espScript
                            hl.OutlineColor = customColors.espScriptOutline
                            hl.FillTransparency = 0.25
                            hl.OutlineTransparency = 0
                            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                            hl.Adornee = plr.Character
                            hl.Parent = plr.Character
                            
                            -- Adicionar seta de identificação na cabeça
                            local arrowGui = Instance.new("BillboardGui")
                            arrowGui.Name = "ScriptArrow"
                            arrowGui.Size = UDim2.new(0, 50, 0, 50)
                            arrowGui.StudsOffset = Vector3.new(0, 3.5, 0)
                            arrowGui.Adornee = plr.Character:FindFirstChild("Head")
                            arrowGui.AlwaysOnTop = true
                            arrowGui.MaxDistance = math.huge
                            arrowGui.Parent = plr.Character
                            
                            local arrowLabel = Instance.new("TextLabel")
                            arrowLabel.Size = UDim2.new(1, 0, 1, 0)
                            arrowLabel.BackgroundTransparency = 1
                            arrowLabel.Text = "▼"
                            arrowLabel.TextColor3 = customColors.espScript -- Laranja
                            arrowLabel.TextStrokeTransparency = 0
                            arrowLabel.TextStrokeColor3 = customColors.espScriptOutline -- Vermelho
                            arrowLabel.TextScaled = true
                            arrowLabel.Font = Enum.Font.GothamBold
                            arrowLabel.Parent = arrowGui
                        elseif not has and esp then
                            esp:Destroy()
                            -- Remover seta também
                            local arrow = plr.Character:FindFirstChild("ScriptArrow")
                            if arrow then arrow:Destroy() end
                        end
                    end
                end
            end
            task.wait(1)
        end
    end)
end

local function removeESPScript()
    espscriptActive = false
    for _, plr in pairs(Players:GetPlayers()) do
        if plr.Character then
            local esp = plr.Character:FindFirstChild("ScriptESP")
            if esp then esp:Destroy() end
            local arrow = plr.Character:FindFirstChild("ScriptArrow")
            if arrow then arrow:Destroy() end
        end
    end
    -- também limpar flags locais para evitar nova marcação até reativar
    -- nenhuma marcação adicional será aplicada pois o loop foi interrompido
end

local function removeESPName()
    for _, player in pairs(Players:GetPlayers()) do
        if player.Character then
            local nameTag = player.Character:FindFirstChild("NameESP")
            if nameTag then nameTag:Destroy() end
        end
    end
    print("ESP Name removido!")
end

-- ESP Brainrot - Encontrar o melhor pet
local function applyESPBrainrot()
    local function parseCompactNumber(text)
        if not text or text == "" then return 0 end
        text = tostring(text)
        -- Remove commas and spaces
        text = text:gsub(",", ""):gsub("%s+", "")
        local num, suffix = text:match("([%d%.]+)([KMBT]?)")
        num = tonumber(num)
        if not num then return 0 end
        local multipliers = { K = 1e3, M = 1e6, B = 1e9, T = 1e12 }
        local m = multipliers[suffix]
        if m then
            return num * m
        end
        return num
    end
    local bestPet = nil
    local bestValue = 0
    local bestPlot = nil
    local bestPodium = nil
    
    -- Verificar todas as plots
    for _, plot in pairs(workspace.Plots:GetChildren()) do
        if plot:FindFirstChild("AnimalPodiums") then
            for _, podium in pairs(plot.AnimalPodiums:GetChildren()) do
                -- Verificar diferentes caminhos possíveis para o AnimalOverhead
                local overhead = nil
                
                -- Tentar caminho 1: Base.Spawn.Attachment.AnimalOverhead
                if podium:FindFirstChild("Base") then
                    local base = podium.Base
                    if base:FindFirstChild("Spawn") then
                        local spawn = base.Spawn
                        if spawn:FindFirstChild("Attachment") then
                            overhead = spawn.Attachment:FindFirstChild("AnimalOverhead")
                        end
                    end
                end
                
                -- Tentar caminho 2: Base.Attachment.AnimalOverhead (caso Spawn não exista)
                if not overhead and podium:FindFirstChild("Base") then
                    local base = podium.Base
                    if base:FindFirstChild("Attachment") then
                        overhead = base.Attachment:FindFirstChild("AnimalOverhead")
                    end
                end
                
                -- Tentar caminho 3: Attachment direto no podium
                if not overhead then
                    overhead = podium:FindFirstChild("Attachment") and podium.Attachment:FindFirstChild("AnimalOverhead")
                end
                
                if overhead and overhead:FindFirstChild("Generation") then
                    local generation = parseCompactNumber(overhead.Generation.Text)
                    if generation > bestValue then
                        bestValue = generation
                        bestPet = overhead
                        bestPlot = plot
                        bestPodium = podium
                    end
                end
            end
        end
    end
    
    if bestPet then
        -- Destacar o melhor pet (podium highlight dourado)
        local highlight = Instance.new("Highlight")
        highlight.Name = "BrainrotESP"
        highlight.FillColor = Color3.fromRGB(255, 215, 0) -- Dourado
        highlight.OutlineColor = Color3.fromRGB(255, 0, 0) -- Vermelho
        highlight.FillTransparency = 0.3
        highlight.OutlineTransparency = 0
        highlight.Adornee = bestPodium
        highlight.Parent = bestPodium

        -- Melhorar os textos existentes do AnimalOverhead (dourados, maiores e através das paredes)
        local overheadGui = bestPet
        if overheadGui and overheadGui:IsA("BillboardGui") then
            overheadGui.Size = UDim2.new(0, 240, 0, 120)
            overheadGui.StudsOffset = Vector3.new(0, 6, 0)
            overheadGui.AlwaysOnTop = true
            overheadGui.MaxDistance = math.huge
            overheadGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

            local gold = Color3.fromRGB(255, 215, 0)
            local function styleLabel(lbl)
                if not lbl or not lbl:IsA("TextLabel") then return end
                -- Salvar originais se ainda não salvo
                if lbl:GetAttribute("BR_Styled") ~= true then
                    lbl:SetAttribute("BR_Styled", true)
                    lbl:SetAttribute("BR_OrigR", lbl.TextColor3.R)
                    lbl:SetAttribute("BR_OrigG", lbl.TextColor3.G)
                    lbl:SetAttribute("BR_OrigB", lbl.TextColor3.B)
                    lbl:SetAttribute("BR_OrigStrokeT", lbl.TextStrokeTransparency)
                    lbl:SetAttribute("BR_OrigScaled", lbl.TextScaled and 1 or 0)
                    lbl:SetAttribute("BR_OrigZ", lbl.ZIndex)
                end
                lbl.TextColor3 = gold
                lbl.TextStrokeTransparency = 0
                lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
                lbl.BackgroundTransparency = 1
                lbl.TextScaled = true
                lbl.ZIndex = 10
            end

            styleLabel(overheadGui:FindFirstChild("DisplayName"))
            styleLabel(overheadGui:FindFirstChild("Generation"))
            styleLabel(overheadGui:FindFirstChild("Mutation"))
            styleLabel(overheadGui:FindFirstChild("Price"))
            styleLabel(overheadGui:FindFirstChild("Rarity"))
            styleLabel(overheadGui:FindFirstChild("Stolen"))

            -- Etiqueta adicional no topo indicando claramente que é o melhor
            local header = overheadGui:FindFirstChild("BrainrotHeader")
            if not header then
                header = Instance.new("TextLabel")
                header.Name = "BrainrotHeader"
                header.Parent = overheadGui
                header.Size = UDim2.new(1, 0, 0, 20)
                header.Position = UDim2.new(0, 0, 0, -22)
                header.BackgroundTransparency = 1
                header.TextScaled = true
                header.Font = Enum.Font.GothamBold
                header.ZIndex = 11
            end
            header.Text = "🏆 MELHOR PET"
            header.TextColor3 = gold
            header.TextStrokeTransparency = 0
            header.TextStrokeColor3 = Color3.fromRGB(0,0,0)
        end
        
        print("ESP Brainrot: Melhor pet encontrado - " .. bestPet.DisplayName.Text .. " (Generation: " .. bestValue .. ")")
    else
        print("ESP Brainrot: Nenhum pet encontrado")
    end
end

local function removeESPBrainrot()
    for _, plot in pairs(workspace.Plots:GetChildren()) do
        if plot:FindFirstChild("AnimalPodiums") then
            for _, podium in pairs(plot.AnimalPodiums:GetChildren()) do
                local highlight = podium:FindFirstChild("BrainrotESP")
                if highlight then highlight:Destroy() end

                -- Tentar reverter propriedades principais dos textos, se existir o AnimalOverhead
                local overhead
                if podium:FindFirstChild("Base") then
                    local base = podium.Base
                    if base:FindFirstChild("Spawn") and base.Spawn:FindFirstChild("Attachment") then
                        overhead = base.Spawn.Attachment:FindFirstChild("AnimalOverhead")
                    end
                    if not overhead and base:FindFirstChild("Attachment") then
                        overhead = base.Attachment:FindFirstChild("AnimalOverhead")
                    end
                end
                if not overhead and podium:FindFirstChild("Attachment") then
                    overhead = podium.Attachment:FindFirstChild("AnimalOverhead")
                end

                if overhead and overhead:IsA("BillboardGui") then
                    overhead.AlwaysOnTop = false
                    local header = overhead:FindFirstChild("BrainrotHeader")
                    if header then header:Destroy() end
                end
            end
        end
    end
    print("ESP Brainrot removido!")
end

-- Remover textos
local function removeTexts()
    local textPaths = {
        {"Shop", "Model", function(model) return model:GetChildren()[39] end, "BillboardGui", "Shop"},
        {"RobuxShop", "Model", "Part", "BillboardGui", "Robux Shop"},
        {"CraftingMachine", "Overhead", "BillboardGui", "Countdown"},
        {"CraftingMachine", "Overhead", "BillboardGui", "DisplayText"},
        {"Events", "Extinct", "Model", "BillboardGui", "Title"},
        {"Events", "Extinct", "Model", "BillboardGui", "Countdown"},
        {"GalaxySpinWheels", "1", "Overhead", "BillboardGui", "Countdown"},
        {"GalaxySpinWheels", "1", "Overhead", "BillboardGui", "DisplayText"}
    }
    
    for _, path in pairs(textPaths) do
        local current = workspace
        for i, step in ipairs(path) do
            if type(step) == "function" then
                current = step(current)
            else
                current = current:FindFirstChild(step)
            end
            if not current then break end
        end
        if current then current.Visible = false end
    end
    print("Textos removidos!")
end

local function restoreTexts()
    local textPaths = {
        {"Shop", "Model", function(model) return model:GetChildren()[39] end, "BillboardGui", "Shop"},
        {"RobuxShop", "Model", "Part", "BillboardGui", "Robux Shop"},
        {"CraftingMachine", "Overhead", "BillboardGui", "Countdown"},
        {"CraftingMachine", "Overhead", "BillboardGui", "DisplayText"},
        {"Events", "Extinct", "Model", "BillboardGui", "Title"},
        {"Events", "Extinct", "Model", "BillboardGui", "Countdown"},
        {"GalaxySpinWheels", "1", "Overhead", "BillboardGui", "Countdown"},
        {"GalaxySpinWheels", "1", "Overhead", "BillboardGui", "DisplayText"}
    }
    
    for _, path in pairs(textPaths) do
        local current = workspace
        for i, step in ipairs(path) do
            if type(step) == "function" then
                current = step(current)
            else
                current = current:FindFirstChild(step)
            end
            if not current then break end
        end
        if current then current.Visible = true end
    end
    print("Textos restaurados!")
end

-- STEAL GUI
local function openStealGui()
    if stealGui then return end
    
    stealGui = Instance.new("ScreenGui")
    stealGui.Name = "UltimateStealGui"
    stealGui.Parent = game.CoreGui

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 107, 0, 39)
    btn.Position = UDim2.new(1, -137, 0.5, -19)
    btn.BackgroundColor3 = Color3.fromRGB(150, 100, 255)
    btn.Font = Enum.Font.GothamBlack
    btn.TextSize = 22
    btn.TextColor3 = Color3.fromRGB(255,255,255)
    btn.Text = "STEAL"
    btn.Parent = stealGui
    
    local corner = Instance.new("UICorner", btn)
    corner.CornerRadius = UDim.new(0, 8)

    local state = 0
    btn.MouseButton1Click:Connect(function()
        local character = LocalPlayer.Character
        if not character then return end
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        
        if state == 0 then
            hrp.CFrame = CFrame.new(hrp.Position.X, 150, hrp.Position.Z)
            btn.Text = "VOLTAR"
            state = 1
        else
            hrp.CFrame = CFrame.new(hrp.Position.X, 10, hrp.Position.Z)
            btn.Text = "STEAL"
            state = 0
        end
    end)
end

local function closeStealGui()
    if stealGui then 
        stealGui:Destroy() 
        stealGui = nil
    end
end

-- Server hop
local function serverHop()
    local req = syn and syn.request or http_request or request
    if not req then
        print("Executor não suporta HTTP request")
        return
    end
    
    local ok, response = pcall(function()
        return req({
            Url = "https://games.roblox.com/v1/games/" .. PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
        })
    end)
    
    if not ok or not response then
        print("Erro ao buscar servidores")
        return
    end
    
    local success, body = pcall(HttpService.JSONDecode, HttpService, response.Body)
    if not success or not body or not body.data then
        print("Falha ao decodificar resposta")
        return
    end
    
    local servers = {}
    for _, v in ipairs(body.data) do
        if v.playing < v.maxPlayers and v.id ~= game.JobId then
            table.insert(servers, v.id)
        end
    end
    
    if #servers > 0 then
        local serverId = servers[math.random(#servers)]
        print("Server Hop para:", serverId)
        TeleportService:TeleportToPlaceInstance(PlaceId, serverId, LocalPlayer)
    else
        print("Nenhum servidor disponível")
    end
end

-- ===============================
-- HTTP helper (para presença/ESP Script)
-- ===============================
httpRequestJson = function(method, url, body)
    local req = syn and syn.request or http_request or request
    if not req then return false, "http_request_not_supported" end
    local payload = {
        Url = url,
        Method = method,
        Headers = { ["Content-Type"] = "application/json" },
        Body = body and HttpService:JSONEncode(body) or nil
    }
    local ok, res = pcall(function() return req(payload) end)
    if not ok or not res then return false, "request_failed" end
    local success, data = pcall(function()
        return res.Body and HttpService:JSONDecode(res.Body) or nil
    end)
    return true, success and data or nil
end

-- Speed function
local function fakeWalk()
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if not boosted then 
            conn:Disconnect() 
            return 
        end
        local moveDir = humanoid.MoveDirection
        if moveDir.Magnitude > 0 then
            hrp.CFrame = hrp.CFrame + moveDir.Unit * speedMultiplier * 0.2
        end
    end)
end

-- ===============================
-- EVENTOS DE INPUT
-- ===============================

UIS.InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.Space and toggles.HighJump then
        local character = LocalPlayer.Character
        if character and character:FindFirstChild("HumanoidRootPart") then
            character.HumanoidRootPart.Velocity = Vector3.new(0, HIGH_JUMP, 0)
        end
    end
end)

-- Anti-fall
if Hum then
    Hum:GetPropertyChangedSignal("FloorMaterial"):Connect(function()
        if Hum.FloorMaterial == Enum.Material.Air and HRP and HRP.Position.Y < -20 then
            HRP.Velocity = Vector3.new(0,100,0)
            end
        end)
end

LocalPlayer.CharacterAdded:Connect(function()
    boosted = false
    Char = LocalPlayer.Character
    Hum = Char:WaitForChild("Humanoid")
    HRP = Char:WaitForChild("HumanoidRootPart")
end)

-- ===============================
-- CRIAR GUI ORIGINAL MELHORADA
-- ===============================

-- Criar GUI principal
local gui = Instance.new("ScreenGui", game.CoreGui)
gui.Name = "UltimateHubV2"

local frame = Instance.new("Frame", gui)
frame.Size = UDim2.new(0, 510, 0, 425)
frame.Position = UDim2.new(0, 30, 0, 30)
frame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
frame.BackgroundTransparency = 0.1
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true

    local function createUICorner(parent, rad)
        local c = Instance.new("UICorner", parent)
        c.CornerRadius = UDim.new(0, rad or 12)
        return c
    end
createUICorner(frame, 12)

    -- Título
local title = Instance.new("TextLabel", frame)
title.Size = UDim2.new(1, -40, 0, 30)
    title.Position = UDim2.new(0, 20, 0, 10)
    title.BackgroundTransparency = 1
title.Text = "🍎 Apple Hub - Premium"
title.Font = Enum.Font.GothamBlack
title.TextSize = 20
title.TextColor3 = Color3.fromRGB(255, 0, 0)
    title.TextXAlignment = Enum.TextXAlignment.Left

-- Linha vermelha
local line = Instance.new("Frame", frame)
line.Size = UDim2.new(1, -20, 0, 2)
line.Position = UDim2.new(0, 10, 0, 45)
line.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
line.BorderSizePixel = 0

-- ===============================
-- SISTEMA DE MINIMIZAR (do Azaro Hub)
-- ===============================
local minimized = false
local miniBtn

-- Botão minimizar
local minimizeBtn = Instance.new("TextButton", frame)
minimizeBtn.Size = UDim2.new(0, 20, 0, 20)
minimizeBtn.Position = UDim2.new(1, -56, 0, 8)
minimizeBtn.Text = ""
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.TextSize = 16
minimizeBtn.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
minimizeBtn.BackgroundTransparency = 0
minimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minimizeBtn.AutoButtonColor = false
createUICorner(minimizeBtn, 6)

-- Ícone de minimizar
local minimizeIcon = Instance.new("ImageLabel", minimizeBtn)
minimizeIcon.Size = UDim2.new(0.7, 0, 0.7, 0)
minimizeIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
minimizeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
minimizeIcon.BackgroundTransparency = 1
minimizeIcon.Image = "rbxassetid://108225148244406"
minimizeIcon.ScaleType = Enum.ScaleType.Fit

minimizeBtn.MouseEnter:Connect(function()
    minimizeBtn.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
end)
minimizeBtn.MouseLeave:Connect(function()
    minimizeBtn.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
end)

local function minimizeMenu()
    minimized = true
    frame.Visible = false
    if miniBtn and miniBtn.Parent then
        miniBtn:Destroy()
        miniBtn = nil
    end
    if not miniBtn then
        miniBtn = Instance.new("TextButton", gui)
        miniBtn.Size = UDim2.new(0, 50, 0, 50)
        miniBtn.Position = UDim2.new(0, 18, 0, 80)
        miniBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        miniBtn.BackgroundTransparency = 0
        miniBtn.AutoButtonColor = false
        miniBtn.Active = true
        miniBtn.Draggable = true
        local round = Instance.new("UICorner", miniBtn)
        round.CornerRadius = UDim.new(1, 0)
        local icon = Instance.new("ImageLabel", miniBtn)
        icon.Size = UDim2.new(1, 0, 1, 0)
        icon.Position = UDim2.new(0.5, 0, 0.5, 0)
        icon.AnchorPoint = Vector2.new(0.5, 0.5)
        icon.BackgroundTransparency = 1
        icon.Image = "rbxassetid://102722891583473"
        icon.ScaleType = Enum.ScaleType.Fit
        local iconCorner = Instance.new("UICorner", icon)
        iconCorner.CornerRadius = UDim.new(1, 0)

        miniBtn.MouseEnter:Connect(function()
            miniBtn.Size = UDim2.new(0, 55, 0, 55)
        end)
        miniBtn.MouseLeave:Connect(function()
            miniBtn.Size = UDim2.new(0, 50, 0, 50)
        end)
        
        miniBtn.MouseButton1Click:Connect(function()
            frame.Visible = true
            minimized = false
            if miniBtn then
                miniBtn:Destroy()
                miniBtn = nil
            end
        end)
    end
end

minimizeBtn.MouseButton1Click:Connect(minimizeMenu)

-- Botão fechar (X)
local closeBtn = Instance.new("TextButton", frame)
closeBtn.Size = UDim2.new(0, 20, 0, 20)
closeBtn.Position = UDim2.new(1, -28, 0, 8)
closeBtn.Text = ""
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 16
closeBtn.BackgroundColor3 = Color3.fromRGB(220, 60, 80)
closeBtn.BackgroundTransparency = 0
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.AutoButtonColor = false
createUICorner(closeBtn, 6)

-- Ícone de fechar
local closeIcon = Instance.new("ImageLabel", closeBtn)
closeIcon.Size = UDim2.new(0.7, 0, 0.7, 0)
closeIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
closeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
closeIcon.BackgroundTransparency = 1
closeIcon.Image = "rbxassetid://5078629701"
closeIcon.ScaleType = Enum.ScaleType.Fit

closeBtn.MouseEnter:Connect(function()
    closeBtn.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
end)
closeBtn.MouseLeave:Connect(function()
    closeBtn.BackgroundColor3 = Color3.fromRGB(220, 60, 80)
end)

closeBtn.MouseButton1Click:Connect(function()
    if gui:FindFirstChild("AppleClosePopup") then return end
    local popup = Instance.new("Frame", gui)
    popup.Name = "AppleClosePopup"
    popup.Size = UDim2.new(0, 340, 0, 170)
    popup.Position = UDim2.new(0.5, -170, 0.5, -85)
    popup.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    popup.BorderSizePixel = 0
    popup.ZIndex = 200
    popup.Active = true
    createUICorner(popup, 12)

    local title = Instance.new("TextLabel", popup)
    title.Size = UDim2.new(1, -32, 0, 32)
    title.Position = UDim2.new(0, 20, 0, 10)
    title.BackgroundTransparency = 1
    title.Text = "Fechar"
    title.Font = Enum.Font.GothamBold
    title.TextSize = 22
    title.TextColor3 = Color3.fromRGB(255,255,255)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextYAlignment = Enum.TextYAlignment.Top
    title.ZIndex = 201

    local msg = Instance.new("TextLabel", popup)
    msg.Size = UDim2.new(1, -40, 0, 48)
    msg.Position = UDim2.new(0, 20, 0, 50)
    msg.BackgroundTransparency = 1
    msg.Text = "Tem certeza que deseja fechar a interface?"
    msg.Font = Enum.Font.Gotham
    msg.TextSize = 18
    msg.TextColor3 = Color3.fromRGB(230,230,230)
    msg.TextXAlignment = Enum.TextXAlignment.Center
    msg.TextYAlignment = Enum.TextYAlignment.Center
    msg.ZIndex = 201

    local btnYes = Instance.new("TextButton", popup)
    btnYes.Size = UDim2.new(0, 120, 0, 36)
    btnYes.Position = UDim2.new(0.5, -128, 1, -54)
    btnYes.BackgroundColor3 = Color3.fromRGB(220, 60, 80)
    btnYes.Text = "Sim"
    btnYes.Font = Enum.Font.GothamBold
    btnYes.TextSize = 17
    btnYes.TextColor3 = Color3.fromRGB(255,255,255)
    btnYes.AutoButtonColor = true
    btnYes.ZIndex = 202
    createUICorner(btnYes, 8)
    btnYes.MouseEnter:Connect(function() btnYes.BackgroundColor3 = Color3.fromRGB(255, 80, 80) end)
    btnYes.MouseLeave:Connect(function() btnYes.BackgroundColor3 = Color3.fromRGB(220, 60, 80) end)

    local btnNo = Instance.new("TextButton", popup)
    btnNo.Size = UDim2.new(0, 120, 0, 36)
    btnNo.Position = UDim2.new(0.5, 8, 1, -54)
    btnNo.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
    btnNo.Text = "Não"
    btnNo.Font = Enum.Font.GothamBold
    btnNo.TextSize = 17
    btnNo.TextColor3 = Color3.fromRGB(255,255,255)
    btnNo.AutoButtonColor = true
    btnNo.ZIndex = 202
    createUICorner(btnNo, 8)
    btnNo.MouseEnter:Connect(function() btnNo.BackgroundColor3 = Color3.fromRGB(100, 100, 140) end)
    btnNo.MouseLeave:Connect(function() btnNo.BackgroundColor3 = Color3.fromRGB(60, 60, 80) end)

    btnYes.MouseButton1Click:Connect(function()
        gui:Destroy()
    end)
    btnNo.MouseButton1Click:Connect(function()
        popup:Destroy()
    end)
end)

-- Abas
local tabNames = { "Funções", "Visual", "Finder", "Server", "Créditos" }
local tabs = {}
local selectedTab = 1

local tabBar = Instance.new("Frame", frame)
tabBar.Size = UDim2.new(1, -20, 0, 30)
tabBar.Position = UDim2.new(0, 10, 0, 55)
tabBar.BackgroundTransparency = 1

local tabWidth = 80
for i, name in ipairs(tabNames) do
    local tab = Instance.new("TextButton", tabBar)
    tab.Size = UDim2.new(0, tabWidth, 0, 24)
    tab.Position = UDim2.new(0, (i-1)*(tabWidth+5), 0, 0)
    tab.Text = name
    tab.Font = Enum.Font.GothamBold
    tab.TextSize = 12
    tab.BackgroundColor3 = (i==1) and Color3.fromRGB(40, 40, 40) or Color3.fromRGB(30, 30, 30)
    tab.TextColor3 = (i==1) and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(180, 180, 180)
    tab.AutoButtonColor = false
    createUICorner(tab, 5)
    tabs[i] = tab
end

local tabFrames = {}
for i=1,#tabNames do
    local f = Instance.new("ScrollingFrame", frame)
    f.Size = UDim2.new(1, -20, 1, -110)
    f.Position = UDim2.new(0, 10, 0, 90)
    f.BackgroundTransparency = 1
    f.ScrollBarThickness = 6
    f.CanvasSize = UDim2.new(0,0,0,600)
    f.Visible = (i==1)
    tabFrames[i] = f
end

local function selectTab(idx)
    for i=1,#tabFrames do
        tabFrames[i].Visible = (i==idx)
        tabs[i].BackgroundColor3 = (i==idx) and Color3.fromRGB(40, 40, 40) or Color3.fromRGB(30, 30, 30)
        tabs[i].TextColor3 = (i==idx) and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(180, 180, 180)
    end
    selectedTab = idx
end

for i,tab in ipairs(tabs) do
    tab.MouseButton1Click:Connect(function() selectTab(i) end)
end

-- Função para criar toggle
local function addToggle(parent, name, position, callback)
    local container = Instance.new("Frame", parent)
    container.Size = UDim2.new(1, -20, 0, 44)
    container.Position = UDim2.new(0, 10, 0, position)
    container.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    createUICorner(container, 8)

    local label = Instance.new("TextLabel", container)
    label.Size = UDim2.new(0.75, 0, 1, 0)
    label.Position = UDim2.new(0, 14, 0, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = 16
    label.TextColor3 = Color3.fromRGB(255, 0, 0)
    label.Text = name
    label.TextXAlignment = Enum.TextXAlignment.Left

    local button = Instance.new("TextButton", container)
    button.Size = UDim2.new(0, 28, 0, 28)
    button.Position = UDim2.new(1, -44, 0.5, -14)
    button.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    button.Text = ""
    button.AutoButtonColor = false
    createUICorner(button, 5)

    button.MouseButton1Click:Connect(function()
        toggles[name] = not toggles[name]
        button.BackgroundColor3 = toggles[name] and Color3.fromRGB(231, 231, 231) or Color3.fromRGB(30, 30, 30)
        callback(toggles[name])
        if toggles[name] then UltimateNotify(name .. " ativado!") end
    end)
    
    -- Armazenar referência para atualização visual
    toggleReferences[name] = {button = button, container = container}
    
    return container
end

-- Função para criar botão
local function addButton(parent, name, position, callback)
    local button = Instance.new("TextButton", parent)
    button.Size = UDim2.new(1, -20, 0, 44)
    button.Position = UDim2.new(0, 10, 0, position)
    button.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    button.Text = name
    button.Font = Enum.Font.GothamBold
    button.TextSize = 16
    button.TextColor3 = Color3.fromRGB(255, 0, 0)
    button.AutoButtonColor = false
    createUICorner(button, 8)
    
    button.MouseEnter:Connect(function()
        button.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    end)
    button.MouseLeave:Connect(function()
        button.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    end)
    
    button.MouseButton1Click:Connect(callback)
    return button
end

-- ABA FUNÇÕES
addToggle(tabFrames[1], "Speed", 10, function(v)
    if v then
        boosted = true
        fakeWalk()
    else
        boosted = false
    end
end)

addToggle(tabFrames[1], "HighJump", 64, function(v)
    -- Já funciona via evento de input
end)

addToggle(tabFrames[1], "Steal", 118, function(v)
    if v then
        openStealGui()
    else
        closeStealGui()
    end
end)

-- ABA VISUAL
addToggle(tabFrames[2], "ESP Name", 10, function(v)
    if v then
        applyESPName()
        task.spawn(function()
            while toggles["ESP Name"] do
                -- Reaplicar para novos players ou reconexões; garantir MaxDistance/AlwaysOnTop
                for _, plr in pairs(Players:GetPlayers()) do
                    if plr ~= LocalPlayer and plr.Character then
                        local head = plr.Character:FindFirstChild("Head")
                        if head then
                            local gui = plr.Character:FindFirstChild("NameESP")
                            if not gui then
                                -- cria novamente
                                local billboardGui = Instance.new("BillboardGui")
                                billboardGui.Name = "NameESP"
                                billboardGui.Size = UDim2.new(0, 80, 0, 20)
                                billboardGui.StudsOffset = Vector3.new(0, 2.5, 0)
                                billboardGui.Adornee = head
                                billboardGui.AlwaysOnTop = true
                                billboardGui.MaxDistance = math.huge
                                billboardGui.Parent = plr.Character
                                local nameLabel = Instance.new("TextLabel")
                                nameLabel.Size = UDim2.new(1, 0, 1, 0)
                                nameLabel.BackgroundTransparency = 1
                                nameLabel.Text = plr.Name
                                nameLabel.TextColor3 = customColors.espName
                                nameLabel.TextStrokeTransparency = 0
                                nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
                                nameLabel.TextScaled = true
                                nameLabel.Font = Enum.Font.GothamBold
                                nameLabel.Parent = billboardGui
                            else
                                gui.AlwaysOnTop = true
                                gui.MaxDistance = math.huge
                            end
                        end
                    end
                end
                task.wait(0.5)
            end
        end)
    else
        removeESPName()
    end
end)

addToggle(tabFrames[2], "ESP Player", 64, function(v)
    if v then
        applyESPPlayer()
    else
        removeESPPlayer()
    end
end)

addToggle(tabFrames[2], "ESP Timer", 118, function(v)
    activeLockTimeEsp = v
    if v then
        for _, instance in pairs(lteInstances) do
            if instance then instance:Destroy() end
        end
        lteInstances = {}
        
        task.spawn(function()
            while activeLockTimeEsp do
                updatelock()
                task.wait(1)
            end
        end)
    else
        updatelock()
    end
end)

-- ESP Script sempre ativo ao iniciar (toggle removido da UI)

addToggle(tabFrames[2], "ESP Brainrot", 172, function(v)
    if v then
        brainrotActive = true
        task.spawn(function()
            while brainrotActive do
                removeESPBrainrot()
                applyESPBrainrot()
                task.wait(0.5)
            end
        end)
    else
        brainrotActive = false
        removeESPBrainrot()
    end
end)

-- ABA FINDER
-- Ranges UI (acima do botão Server Hop)
do
    local function createRangeToggleUI(parent, labelText, key, y)
        local container = Instance.new("Frame", parent)
        container.Size = UDim2.new(1, -20, 0, 44)
        container.Position = UDim2.new(0, 10, 0, y)
        container.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
        local c = Instance.new("UICorner", container)
        c.CornerRadius = UDim.new(0, 8)

        local label = Instance.new("TextLabel", container)
        label.Size = UDim2.new(0.75, 0, 1, 0)
        label.Position = UDim2.new(0, 14, 0, 0)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.GothamBold
        label.TextSize = 16
        label.TextColor3 = Color3.fromRGB(255, 0, 0)
        label.Text = labelText
        label.TextXAlignment = Enum.TextXAlignment.Left

        local button = Instance.new("TextButton", container)
        button.Size = UDim2.new(0, 56, 0, 28)
        button.Position = UDim2.new(1, -72, 0.5, -14)
        button.BackgroundColor3 = Color3.fromRGB(255, 64, 64)
        button.Text = "OFF"
        button.Font = Enum.Font.GothamBold
        button.TextSize = 12
        button.TextColor3 = Color3.fromRGB(255, 0, 0)
        button.AutoButtonColor = false
        local bc = Instance.new("UICorner", button)
        bc.CornerRadius = UDim.new(0, 6)

        local function refresh()
            if enabledRanges[key] then
                button.BackgroundColor3 = Color3.fromRGB(64, 200, 96)
                button.Text = "ON"
                container.BackgroundColor3 = Color3.fromRGB(36, 48, 36)
            else
                button.BackgroundColor3 = Color3.fromRGB(255, 64, 64)
                button.Text = "OFF"
                container.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
            end
        end

        button.MouseButton1Click:Connect(function()
            enabledRanges[key] = not enabledRanges[key]
            refresh()
        end)

        refresh()
        return container
    end

    local y0 = 10
    createRangeToggleUI(tabFrames[3], "1M - 10M", "micro", y0)
    createRangeToggleUI(tabFrames[3], "10M - 50M", "low", y0 + 54)
    createRangeToggleUI(tabFrames[3], "50M - 100M", "mid", y0 + 108)
    createRangeToggleUI(tabFrames[3], "100M - 500M", "high", y0 + 162)
    createRangeToggleUI(tabFrames[3], "500M - 10B", "ultra", y0 + 216)

    -- Botão existente de Server Hop
    addButton(tabFrames[3], "Procurar Server Bom", y0 + 270, function()
        serverHop()
    end)
    
    -- Botão para salvar configurações
    addButton(tabFrames[3], "💾 Salvar Configurações", y0 + 324, function()
        saveSettings()
    end)
end

-- ABA SERVER
addToggle(tabFrames[4], "Tema Color", 10, function(v)
    if v then
        applyPurpleNeonTheme()
    else
        resetToDefaultTheme()
    end
end)

addToggle(tabFrames[4], "Bases Transparência", 64, function(v)
    if v then
        applyTransparency()
    else
        resetTransparency()
    end
end)

addToggle(tabFrames[4], "Chão Transparente", 118, function(v)
    if v then
        applyChaoTransparency()
    else
        resetChaoTransparency()
    end
end)

addToggle(tabFrames[4], "Shops Transparente", 172, function(v)
    if v then
        applyShopsTransparency()
    else
        resetShopsTransparency()
        end
    end)

addToggle(tabFrames[4], "Maquina Transparente", 226, function(v)
    if v then
        applyMaquinaTransparency()
    else
        resetMaquinaTransparency()
    end
end)

addToggle(tabFrames[4], "Roleta Transparente", 280, function(v)
    if v then
        applyRoletaTransparency()
    else
        resetRoletaTransparency()
    end
end)

addToggle(tabFrames[4], "Remover Textos", 334, function(v)
    if v then
        removeTexts()
    else
        restoreTexts()
    end
end)

-- ABA CRÉDITOS
local creditLabel = Instance.new("TextLabel", tabFrames[5])
creditLabel.Size = UDim2.new(1, -20, 0, 300)
creditLabel.Position = UDim2.new(0, 10, 0, 10)
creditLabel.BackgroundTransparency = 1
creditLabel.Text = [[
🍎 Apple Hub - Notifier e Auto-Joiner


📅 Última Atualização: ]] .. os.date("%d/%m/%Y") .. [[

🏆 O maior e melhor servidor de notifier e auto-joiner!
]]
creditLabel.TextColor3 = Color3.fromRGB(148, 11, 1)
creditLabel.Font = Enum.Font.Gotham
creditLabel.TextSize = 14
creditLabel.TextYAlignment = Enum.TextYAlignment.Top
creditLabel.TextWrapped = true

-- Botão Discord
local discordBtn = Instance.new("TextButton", tabFrames[5])
discordBtn.Size = UDim2.new(1, -20, 0, 44)
discordBtn.Position = UDim2.new(0, 10, 0, 320)
discordBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
discordBtn.Text = "📱 Discord Server"
discordBtn.Font = Enum.Font.GothamBold
discordBtn.TextSize = 16
discordBtn.TextColor3 = Color3.fromRGB(255, 0, 0)
discordBtn.AutoButtonColor = false
createUICorner(discordBtn, 8)

discordBtn.MouseEnter:Connect(function()
    discordBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
end)
discordBtn.MouseLeave:Connect(function()
    discordBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
end)

discordBtn.MouseButton1Click:Connect(function()
    setclipboard("https://discord.gg/applehub")
    UltimateNotify("O link foi copiado, cole em seu navegador!")
end)

-- ===============================
-- BOTÃO AUTO-JOIN NA TELA (como no apple-joiner.lua)
-- ===============================
local autoJoinScreenBtn = Instance.new("Frame", gui)
autoJoinScreenBtn.Name = "AutoJoinScreenBtn"
autoJoinScreenBtn.Size = UDim2.new(0, 200, 0, 50)
autoJoinScreenBtn.Position = UDim2.new(0, 20, 0, 20)
autoJoinScreenBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
autoJoinScreenBtn.BorderSizePixel = 0
autoJoinScreenBtn.Visible = true

local autoJoinScreenCorner = Instance.new("UICorner", autoJoinScreenBtn)
autoJoinScreenCorner.CornerRadius = UDim.new(0, 8)

local autoJoinScreenButton = Instance.new("TextButton", autoJoinScreenBtn)
autoJoinScreenButton.Name = "AutoJoinScreenButton"
autoJoinScreenButton.Size = UDim2.new(1, 0, 1, 0)
autoJoinScreenButton.Position = UDim2.new(0, 0, 0, 0)
autoJoinScreenButton.BackgroundTransparency = 1
autoJoinScreenButton.Text = "Auto-Join: OFF"
autoJoinScreenButton.TextColor3 = Color3.fromRGB(255, 0, 0)
autoJoinScreenButton.TextScaled = false
autoJoinScreenButton.TextSize = 16
autoJoinScreenButton.Font = Enum.Font.GothamBold
autoJoinScreenButton.Parent = autoJoinScreenBtn

local function anyRangeEnabled()
    for _, v in pairs(enabledRanges) do if v then return true end end
    return false
end

local function updateAutoJoinButton()
    if isAutoJoinRunning then
        autoJoinScreenButton.Text = "Auto-Join: ON"
        autoJoinScreenButton.TextColor3 = Color3.fromRGB(0, 255, 0)
    else
        autoJoinScreenButton.Text = "Auto-Join: OFF"
        autoJoinScreenButton.TextColor3 = Color3.fromRGB(255, 0, 0)
    end
end

autoJoinScreenButton.MouseButton1Click:Connect(function()
    if isAutoJoinRunning then
        isAutoJoinRunning = false
        warn("[APPLE-JOINER V2] Auto-join STOPPED by user")
    else
        if not anyRangeEnabled() then
            UltimateNotify("Selecione pelo menos um range antes de iniciar o Auto-Join")
            return
        end
        isAutoJoinRunning = true
        warn("[APPLE-JOINER V2] Auto-join STARTED by user")
        startAutoJoin()
    end
    updateAutoJoinButton()
end)

updateAutoJoinButton()

-- Tecla F para abrir/fechar
UIS.InputBegan:Connect(function(Input)
    if Input.KeyCode == Enum.KeyCode.F then
        gui.Enabled = not gui.Enabled
    end
end)

-- Carregar configurações salvas e ativar ESP Script automaticamente ao iniciar
task.defer(function()
    -- Carregar configurações salvas primeiro
    local loaded = loadSettings()
    
    -- Aplicar configurações carregadas
    if loaded then
        -- Aplicar toggles ativos (exceto ESPs que serão aplicados depois)
        for toggleName, isActive in pairs(toggles) do
            if isActive then
                if toggleName == "Speed" then
                    applySpeed()
                elseif toggleName == "HighJump" then
                    applyHighJump()
                elseif toggleName == "Steal" then
                    applySteal()
                elseif toggleName == "ESP Timer" then
                    activeLockTimeEsp = true
                    task.spawn(function()
                        while activeLockTimeEsp do
                            updatelock()
                            task.wait(1)
                        end
                    end)
                elseif toggleName == "Tema Color" then
                    applyPurpleNeonTheme()
                elseif toggleName == "Bases Transparência" then
                    applyTransparency()
                elseif toggleName == "Shops Transparente" then
                    applyShopsTransparency()
                elseif toggleName == "Maquina Transparente" then
                    applyMaquinaTransparency()
                elseif toggleName == "Roleta Transparente" then
                    applyRoletaTransparency()
                elseif toggleName == "Chão Transparente" then
                    applyChaoTransparency()
                elseif toggleName == "Remover Textos" then
                    removeTexts()
                end
            end
        end
        
        -- Aplicar ESPs na ordem correta (Script por último para ficar por cima)
        if toggles["ESP Name"] then
            applyESPName()
        end
        
        if toggles["ESP Player"] then
            applyESPPlayer()
        end
        
        if toggles["ESP Brainrot"] then
            applyESPBrainrot()
        end
        
        -- Aplicar auto-join se ativo
        if autoJoinActive then
            startAutoJoin()
        end
        
        -- Atualizar toggles visuais na GUI
        updateToggleVisuals()
        
        print("🔄 Configurações aplicadas automaticamente!")
    end
    
    -- Sempre ativar ESP Script por último para ficar por cima de todos
    applyESPScript()
end)

-- Cleanup ao sair
game:GetService("Players").PlayerRemoving:Connect(function(player)
    if player == LocalPlayer then
        -- Desativar todas as funções
        for k in pairs(toggles) do toggles[k] = false end
        
        -- Limpar efeitos
        removeESPPlayer()
        removeESPName()
        removeESPBrainrot()
        resetToDefaultTheme()
        resetTransparency()
        resetShopsTransparency()
        resetMaquinaTransparency()
        resetRoletaTransparency()
        resetChaoTransparency()
        restoreTexts()
        closeStealGui()
        
        -- Limpar ESP Timer
        for _, instance in pairs(lteInstances) do
            if instance then instance:Destroy() end
        end
    end
end)

-- ===============================
-- INICIALIZAÇÃO COMPLETA
-- ===============================

print("🚀 Apple Hub v2.0.0 carregado com sucesso!")
print("💡 Pressione F para abrir/fechar a interface")
print("✨ Nova UI: Luminosity Library - Muito mais bonita!")
print("🎯 Todas as funcionalidades migradas com sucesso!")