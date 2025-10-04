repeat task.wait() until game:IsLoaded()

-- ===============================
-- Configurações iniciais
-- ===============================
local http_service = game:GetService("HttpService")
local teleport_service = game:GetService("TeleportService")
local players = game:GetService("Players")

local place_id = tostring(game.PlaceId)
local job_id = game.JobId
local http_request = request or http_request or syn.request

-- API Railway
local SERVER_URL = "https://apple-joiner-production.up.railway.app"
local API_KEY = "Apple2502!@"

-- Webhooks Discord
local webhook_verylow = "https://discord.com/api/webhooks/1422189894171627612/zzjNGcVA7GI6W6uz0uQsJX9b1ritiORNWWAWu-JMYkXj8LnQtv7oYqxpZjE781L6TFUl"
local webhook_low = "https://discord.com/api/webhooks/1420454735005224991/duVLVLgOFqf8s889Xil8GEs_4j92BMLjvTzrwhWdSqbrZ_AgKapwSzhEnXTTEMiujRlh"
local webhook_mid = "https://discord.com/api/webhooks/1420455204431728782/G_qrdk4-fgHehPPxY30WmhBR_t7ajD3zoDa0XhWK-rjkJ4_KEv6UhLbF9NaNT39k65k2"
local webhook_high = "https://discord.com/api/webhooks/1420455382211625091/fXdNYskhCVHlFsHi8iO1y6pmWhQT0FNm5AJw9jPTVs_gyTBtVTyHPPZSAPEisrv54ocQ"
local webhook_highm = "https://discord.com/api/webhooks/1420455623891488898/ZWrnpGFZoWeujQTry9RovzpuFrU7Dv_IsIARnPTriQyaE55N6x-uEmDL5SQyRyJOYOxZ"
local webhook_clutch = "https://discord.com/api/webhooks/1422576785794531412/dl6ioAESueEhJ8zHwafCFnt-GqbnzdxUlJj99rYcvZ4pkqAKkJegY3YHF7cK-chWeyCN"

-- Ranges
local verylow_min, verylow_max = 1000000, 10000000
local low_min, low_max = 10000000, 50000000
local mid_min, mid_max = 50000000, 100000000
local high_min, high_max = 100000000, 500000000
local highm_min, highm_max = 500000000, 100000000000

-- Cache local
local last_sent_data = {}

-- ===============================
-- Helpers HTTP
-- ===============================
local function post_json(url, body_tbl)
    return pcall(function()
        return http_request({
            Url = url,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["x-api-key"] = API_KEY
            },
            Body = http_service:JSONEncode(body_tbl)
        })
    end)
end

local function get_json(url)
    local ok, resp = pcall(function()
        return http_request({
            Url = url,
            Method = "GET",
            Headers = {
                ["x-api-key"] = API_KEY
            }
        })
    end)
    if not ok or not resp or not resp.Body then return nil end
    local ok2, data = pcall(http_service.JSONDecode, http_service, resp.Body)
    if not ok2 then return nil end
    return data
end

-- ===============================
-- Verificação de Blacklist
-- ===============================
local function is_blacklisted(jobId)
    local data = get_json(SERVER_URL .. "/blacklist/check/" .. jobId)
    return data and data.blacklisted
end

local function add_to_blacklist(jobId)
    post_json(SERVER_URL .. "/blacklist/add", {
        jobId = jobId,
        reason = "already_visited"
    })
    print("[APPLE] 🛑 Job ID adicionado à blacklist: " .. jobId)
end

-- ===============================
-- Envio para servidor
-- ===============================
local function send_to_server(jobId, petName, petValue, range)
    if not jobId or not petName or not petValue or not range then return end
    post_json(SERVER_URL .. "/submit", {
        jobId = jobId,
        petName = petName,
        petValue = petValue,
        range = range
    })
    print("[APPLE] 🌐 Enviado ao servidor:", petName, petValue, jobId)
end

-- ===============================
-- Envio para o Discord
-- ===============================
local function get_short_link(url)
    local ok, resp = pcall(function()
        return http_request({
            Url = "https://api.tinyurl.com/create",
            Method = "POST",
            Headers = {
                ["Authorization"] = "Bearer " .. API_KEY,
                ["Content-Type"] = "application/json"
            },
            Body = http_service:JSONEncode({ url = url })
        })
    end)
    if ok and resp and resp.Body then
        local ok2, data = pcall(http_service.JSONDecode, http_service, resp.Body)
        if ok2 and data.data and data.data.tiny_url then
            return data.data.tiny_url
        end
    end
    return url
end

local function send_discord(best_by_plot)
    local join_link = get_short_link("roblox://placeId=" .. place_id .. "&gameInstanceId=" .. job_id)

    local function send_webhook(url, section)
        for plot_name, best in pairs(best_by_plot) do
            if best.section ~= section then continue end
            local combined_key = plot_name .. ":" .. best.info
            if last_sent_data[combined_key] then continue end
            last_sent_data[combined_key] = true

            local embed = {
                title = plot_name,
                description = "**Players in server:** " .. #players:GetPlayers() .. "/8\n**Job ID - (PC):** " .. "```" .. job_id .. "```" .. "\n**Job ID - (MOB):** " .. "`" .. job_id .. "`",
                color = 16722988,
                fields = {
                    { name = "**Animal**", value = "- " .. best.info, inline = false },
                    { name = "**Join link**", value = join_link, inline = false }
                },
                timestamp = os.date("!%Y-%m-%dT%H:%M:%S.000Z")
            }

            local line_text = "1x " .. (best.animal or "?") .. " (" .. (best.value_text or "?") .. ")"
            local clutch_embed = {
                title = line_text,
                color = 16722988,
                fields = {
                    { name = "🐒 Brainrots", value = plot_name, inline = false },
                    { name = " ", value = "```" .. line_text .. "```", inline = false }
                },
                timestamp = os.date("!%Y-%m-%dT%H:%M:%S.000Z")
            }

            -- Envia embed normal
            pcall(function()
                http_request({
                    Url = url,
                    Method = "POST",
                    Headers = { ["Content-Type"] = "application/json" },
                    Body = http_service:JSONEncode({ embeds = { embed } }),
                })
            end)

            -- Envia clutch se não for verylow
            if best.section ~= "verylow" then
                pcall(function()
                    http_request({
                        Url = webhook_clutch,
                        Method = "POST",
                        Headers = { ["Content-Type"] = "application/json" },
                        Body = http_service:JSONEncode({ embeds = { clutch_embed } }),
                    })
                end)
            end
        end
    end

    send_webhook(webhook_verylow, "verylow")
    send_webhook(webhook_low, "low")
    send_webhook(webhook_mid, "mid")
    send_webhook(webhook_high, "high")
    send_webhook(webhook_highm, "ultra")
end

-- ===============================
-- Scanner de Pets
-- ===============================
local function scan_and_report()
    local best_by_plot = {}
    local total_pets_found = 0

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
                            if value >= highm_min then
                                section = "ultra"
                            elseif value >= high_min then
                                section = "high"
                            elseif value >= mid_min and value <= mid_max then
                                section = "mid"
                            elseif value >= low_min and value <= low_max then
                                section = "low"
                            end
                            if section then
                                local info = display_name.Text .. " - " .. generation.Text
                                local current = best_by_plot[plot_name]
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
        for plot, best in pairs(best_by_plot) do
            local key = plot .. ":" .. best.info
            if not last_sent_data[key] then
                last_sent_data[key] = true
                send_to_server(job_id, best.animal or plot, best.value or 0, best.section)
            end
        end
        -- Envia para Discord
        send_discord(best_by_plot)
        return true
    else
        return false
    end
end

-- ===============================
-- Server Hop com Blacklist
-- ===============================
local function server_hop(range)
    local jobs = get_json(SERVER_URL .. "/jobs/" .. range)
    if not jobs or #jobs == 0 then
        print("[APPLE] ❌ Nenhum job disponível no range:", range)
        return
    end

    local available_jobs = {}

    -- Filtra os jobs não presentes na blacklist
    for _, job in ipairs(jobs) do
        if not is_blacklisted(job.jobId) then
            table.insert(available_jobs, job)
        end
    end

    -- Se houver jobs disponíveis que não foram visitados, escolhe aleatoriamente
    if #available_jobs > 0 then
        local selected_job = available_jobs[math.random(1, #available_jobs)]
        add_to_blacklist(selected_job.jobId)  -- Adiciona o job à blacklist

        -- Teleporta para o job selecionado
        print("[APPLE] 🔄 Hop para", selected_job.jobId)
        teleport_service:TeleportToPlaceInstance(place_id, selected_job.jobId, players.LocalPlayer)
    else
        print("[APPLE] ❌ Nenhum servidor disponível que não tenha sido visitado.")
    end
end

-- ===============================
-- Loop principal
-- ===============================
while true do
    if workspace and workspace:FindFirstChild("Plots") then
        local found = scan_and_report()
        task.wait(1)
        server_hop("low")
        server_hop("mid")
        server_hop("high")
        server_hop("ultra")
    else
        server_hop("low")
    end
    task.wait(2)
end
