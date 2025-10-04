repeat task.wait() until game:IsLoaded()

-- Remover/ocultar loading screens para agilizar início
pcall(function()
    local pg = players.LocalPlayer and players.LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then
        pg = players.LocalPlayer:WaitForChild("PlayerGui", 2)
    end
    if pg then
        for _, gui in ipairs(pg:GetChildren()) do
            if gui:IsA("ScreenGui") and (string.find(string.lower(gui.Name), "load") or string.find(string.lower(gui.Name), "loading") or string.find(string.lower(gui.Name), "intro")) then
                gui.Enabled = false
                gui.ResetOnSpawn = false
            end
        end
    end
    local core = game:GetService("CoreGui")
    for _, gui in ipairs(core:GetChildren()) do
        if gui:IsA("ScreenGui") and (string.find(string.lower(gui.Name), "load") or string.find(string.lower(gui.Name), "loading") or string.find(string.lower(gui.Name), "intro")) then
            gui.Enabled = false
        end
    end
end)

-- Força remoção de "LoadingScreen" do CoreGui do Roblox (quando aplicável)
pcall(function()
    local core = game:GetService("CoreGui")
    local ls = core:FindFirstChild("RobloxLoadingGui") or core:FindFirstChild("LoadingGui") or core:FindFirstChild("DefaultLoadingGui")
    if ls and ls:IsA("LayerCollector") then
        ls.Enabled = false
    end
end)

-- Reduz qualidade grafica ao minimo
local lighting = game:GetService("Lighting")
lighting.Technology = Enum.Technology.Compatibility
print("[RUBY NOTIFY] Qualidade grafica reduzida")

local user_settings = UserSettings()
local game_settings = user_settings.GameSettings
if game_settings then
    pcall(function()
        game_settings.MasterVolume = 0
    end)
end
print("[RUBY NOTIFY] Audio desabilitado")

-- Reduz FPS para economizar recursos
if setfpscap then 
    setfpscap(15) 
    print("[RUBY NOTIFY] FPS limitado a 15")
end

-- ===============================
-- Configurações iniciais
-- ===============================
local http_service = game:GetService("HttpService")
local teleport_service = game:GetService("TeleportService")
local players = game:GetService("Players")

repeat task.wait() until players.LocalPlayer

local place_id = tostring(game.PlaceId)
local job_id = game.JobId
local previous_job_id = job_id
local http_request = request or http_request or syn.request

-- API Railway (server.js)
local SERVER_URL = "https://apple-joiner-production.up.railway.app"
local API_KEY = "Apple2502!@"

local webhook_verylow = "https://discord.com/api/webhooks/1422189894171627612/zzjNGcVA7GI6W6uz0uQsJX9b1ritiORNWWAWu-JMYkXj8LnQtv7oYqxpZjE781L6TFUl"
local webhook_low = "https://discord.com/api/webhooks/1420454735005224991/duVLVLgOFqf8s889Xil8GEs_4j92BMLjvTzrwhWdSqbrZ_AgKapwSzhEnXTTEMiujRlh"
local webhook_mid = "https://discord.com/api/webhooks/1420455204431728782/G_qrdk4-fgHehPPxY30WmhBR_t7ajD3zoDa0XhWK-rjkJ4_KEv6UhLbF9NaNT39k65k2"
local webhook_high = "https://discord.com/api/webhooks/1420455382211625091/fXdNYskhCVHlFsHi8iO1y6pmWhQT0FNm5AJw9jPTVs_gyTBtVTyHPPZSAPEisrv54ocQ"
local webhook_highm = "https://discord.com/api/webhooks/1420455623891488898/ZWrnpGFZoWeujQTry9RovzpuFrU7Dv_IsIARnPTriQyaE55N6x-uEmDL5SQyRyJOYOxZ"
local webhook_clutch = "https://discord.com/api/webhooks/1422576785794531412/dl6ioAESueEhJ8zHwafCFnt-GqbnzdxUlJj99rYcvZ4pkqAKkJegY3YHF7cK-chWeyCN"

local verylow_min, verylow_max = 1000000, 10000000
local low_min, low_max = 10000000, 50000000
local mid_min, mid_max = 50000000, 100000000
local high_min, high_max = 100000000, 500000000
local highm_min, highm_max = 500000000, 100000000000
local api_token = "xlZU4uKzcBpSKx4WSbK1NT6lrJMOq0gTXWWD7whc8J6L3VNeMYtrqFkhUOSk" 
local last_sent_data = {}

-- ===============================
-- Função de scan de pets
local function scan_and_report()
    print("[RUBY NOTIFY] 🔍 Scan rápido...")

    -- Verificar se workspace.Plots existe
    if not workspace:FindFirstChild("Plots") then
        print("[RUBY NOTIFY] Erro: Não foi possível encontrar 'Plots' no workspace.")
        return false
    end

    -- Melhor pet por base
    local best_by_plot = {} -- [plot] = { value = number, info = string, section = string }
    local total_pets_found = 0

    -- Itera por todos os plots no workspace
    for _, plot in pairs(workspace.Plots:GetChildren()) do
        local plot_name = get_plot_display_name(plot)
        local podiums = plot:FindFirstChild("AnimalPodiums", true)
        
        if podiums then
            for _, podium in pairs(podiums:GetChildren()) do
                local base = podium:FindFirstChild("Base", true)
                if base and base:FindFirstChild("Spawn") then
                    local spawn = base.Spawn
                    local attachment = spawn:FindFirstChild("Attachment")
                    local overhead_ui = attachment and attachment:FindFirstChild("AnimalOverhead")

                    if overhead_ui then
                        local generation = overhead_ui:FindFirstChild("Generation")
                        local display_name = overhead_ui:FindFirstChild("DisplayName")

                        if generation and display_name then
                            local value = parse_amount(generation.Text)
                            local section = nil

                            -- Classificar o valor
                            if value >= highm_min then
                                section = "highm"
                            elseif value >= high_min then
                                section = "high"
                            elseif value >= mid_min and value <= mid_max then
                                section = "mid"
                            elseif value >= low_min and value <= low_max then
                                section = "low"
                            elseif value >= verylow_min and value <= verylow_max then
                                section = "verylow"
                            end

                            if section then
                                local info = display_name.Text .. " - " .. generation.Text
                                local current = best_by_plot[plot_name]
                                
                                -- Armazenar o melhor pet por base
                                if not current or value > current.value then
                                    best_by_plot[plot_name] = {
                                        value = value,
                                        info = info,
                                        section = section,
                                        animal = display_name.Text,
                                        value_text = generation.Text
                                    }
                                end
                                total_pets_found = total_pets_found + 1
                            end
                        end
                    end
                end
            end
        end
    end

    if next(best_by_plot) ~= nil then
        print("[RUBY NOTIFY] ✅ " .. total_pets_found .. " pets encontrados. Enviando o melhor por base...")

        for plot, best in pairs(best_by_plot) do
            local key = plot .. ":" .. best.info
            if not last_sent_data[key] then
                last_sent_data[key] = true

                send_to_server(job_id, best.animal or plot, best.value or 0, best.section)

                local embed = {
                    title = plot,
                    description = "**Players in server:** " .. #players:GetPlayers() .. "/8\n**Job ID - (PC):** " .. "```" .. job_id .. "```" .. "\n**Job ID - (MOB):** " .. "`" .. job_id .. "`",
                    color = 16722988,
                    fields = {
                        { name = "**Animal**", value = "- " .. best.info, inline = false },
                        { name = "**Join link**", value = get_short_link("roblox://placeId=" .. place_id .. "&gameInstanceId=" .. job_id), inline = false }
                    }
                }

                -- Envia para o Discord
                local url = webhook_for_section(best.section)
                if url then
                    pcall(function()
                        http_request({
                            Url = url,
                            Method = "POST",
                            Headers = { ["Content-Type"] = "application/json" },
                            Body = http_service:JSONEncode({ embeds = { embed } })
                        })
                    end)
                end
            end
        end
        return true
    else
        print("[RUBY NOTIFY] ❌ Nada encontrado - HOP IMEDIATO!")
        return false
    end
end
-- ===============================
-- Função de Server Hop
-- ===============================
local function alternateServersRequest()
    local response = request({
        Url = 'https://games.roblox.com/v1/games/' .. tostring(game.PlaceId) .. '/servers/Public?sortOrder=Asc&limit=100',
        Method = "GET",
        Headers = { ["Content-Type"] = "application/json" },
    })

    if response.Success then
        return response.Body
    else
        return nil
    end
end

local function getServer()
    local servers

    local success, _ = pcall(function()
        servers = game.HttpService:JSONDecode(game:HttpGet('https://games.roblox.com/v1/games/' .. tostring(game.PlaceId) .. '/servers/Public?sortOrder=Asc&limit=100')).data
    end)

    if not success then
        print("Error getting servers, using backup method")
        servers = game.HttpService:JSONDecode(alternateServersRequest()).data
    end

    local server = servers[Random.new():NextInteger(5, 100)]
    if server then
        return server
    else
        return getServer()
    end
end

pcall(function()
    game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, getServer().id, game.Players.LocalPlayer)
end)

task.wait(5)

-- ===============================
-- Loop principal
-- ===============================
while true do
    if workspace and workspace:FindFirstChild("Plots") then
        local found = scan_and_report()  -- Primeiro, faz o scan
        if not found then  -- Se não encontrar, faz o server hop
            server_hop()
        end
        task.wait(1)
    else
        task.wait(2)
    end
end
