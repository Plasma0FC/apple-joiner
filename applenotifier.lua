repeat task.wait() until game:IsLoaded()

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

local RANGE_PRIORITY = { "ultra", "high", "mid", "low" }

-- Cache local
local last_sent_data = {}

local local_player = players.LocalPlayer
local account_id = local_player and tostring(local_player.UserId) or "unknown"
local agent_identifier = (local_player and local_player.Name or "anon") .. "-" .. http_service:GenerateGUID(false)

-- ===============================
-- Helpers HTTP
-- ===============================
local function server_request(method, path, body_tbl)
    local request_data = {
        Url = SERVER_URL .. path,
        Method = method,
        Headers = {
            ["x-api-key"] = API_KEY
        }
    }

    if body_tbl then
        request_data.Headers["Content-Type"] = "application/json"
        request_data.Body = http_service:JSONEncode(body_tbl)
    end

    local ok, resp = pcall(function()
        return http_request(request_data)
    end)

    if not ok or not resp then
        warn("[APPLE] Falha ao se comunicar com " .. path)
        return nil
    end

    local result = {}
    if resp.Body and resp.Body ~= "" then
        local ok_json, decoded = pcall(http_service.JSONDecode, http_service, resp.Body)
        if ok_json and type(decoded) == "table" then
            result = decoded
        end
    end

    result.status = resp.StatusCode
    return result
end

local function server_get(path)
    return server_request("GET", path)
end

local function server_post(path, body_tbl)
    return server_request("POST", path, body_tbl)
end

-- ===============================
-- Blacklist
-- ===============================
local function add_to_blacklist(jobId)
    if not jobId then return end
    server_post("/blacklist/add", {
        jobId = jobId,
        reason = "already_visited"
    })
    print("[APPLE] 🛑 Job ID adicionado à blacklist: " .. jobId)
end

-- ===============================
-- Envio para servidor
-- ===============================
local function send_to_server(jobId, petName, petValue, range)
    if not jobId or not petName or petValue == nil or not range then return end
    server_post("/submit", {
        jobId = jobId,
        petName = petName,
        petValue = petValue,
        range = range,
        accountId = account_id
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

            pcall(function()
                http_request({
                    Url = url,
                    Method = "POST",
                    Headers = { ["Content-Type"] = "application/json" },
                    Body = http_service:JSONEncode({ embeds = { embed } }),
                })
            end)

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
-- Helpers utilitárias
-- ===============================
local SUFFIXES = {
    K = 1e3,
    M = 1e6,
    B = 1e9,
    T = 1e12,
    QA = 1e15,
    QI = 1e18,
    SX = 1e21,
    SP = 1e24,
    OC = 1e27,
    NO = 1e30,
    DC = 1e33
}

local function parse_amount(text)
    if not text then
        return 0
    end
    local cleaned = tostring(text):upper():gsub("%s", "")
    local numeric = tonumber(cleaned)
    if numeric then
        return numeric
    end

    local value_part, suffix_part = cleaned:match("([%d%.]+)([A-Z]+)")
    if value_part and suffix_part then
        local suffix_value = SUFFIXES[suffix_part]
        if suffix_value then
            return tonumber(value_part) * suffix_value
        end
    end

    return 0
end

local function get_plot_display_name(plot)
    if not plot then
        return "UnknownPlot"
    end

    local attribute_name = plot:GetAttribute("DisplayName")
    if attribute_name and attribute_name ~= "" then
        return tostring(attribute_name)
    end

    local billboard = plot:FindFirstChildWhichIsA("BillboardGui", true)
    if billboard then
        local label = billboard:FindFirstChildWhichIsA("TextLabel", true)
        if label and label.Text and label.Text ~= "" then
            return label.Text
        end
    end

    return plot.Name
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
        send_discord(best_by_plot)
        return true
    else
        return false
    end
end

-- ===============================
-- Server Hop via claim exclusivo
-- ===============================
local function claim_and_hop(range)
    local response = server_post("/jobs/claim", {
        range = range,
        agentId = agent_identifier,
        currentJobId = job_id
    })

    if not response then
        print("[APPLE] ⚠️ Falha ao conversar com o servidor (" .. range .. ")")
        return false
    end

    if response.status and response.status >= 400 then
        print("[APPLE] ❌ Erro " .. response.status .. " ao solicitar job (" .. range .. ")")
        return false
    end

    if not response.success or not response.job then
        if response.reason then
            print("[APPLE] ⚪ " .. range .. " sem job: " .. response.reason)
        else
            print("[APPLE] ⚪ Nenhum job disponível em " .. range)
        end
        return false
    end

    local job_info = response.job
    if not job_info.jobId then
        print("[APPLE] ⚠️ Resposta sem jobId válido.")
        return false
    end

    if job_info.jobId == job_id then
        print("[APPLE] ⏭️ Job retornado é o atual, ignorando.")
        return false
    end

    print("[APPLE] 🔄 Hop para " .. job_info.jobId .. " (" .. range .. ")")
    teleport_service:TeleportToPlaceInstance(place_id, job_info.jobId, players.LocalPlayer)
    return true
end

local function hop_next_available()
    for _, range in ipairs(RANGE_PRIORITY) do
        if claim_and_hop(range) then
            return true
        end
        task.wait(0.3)
    end
    return false
end

-- ===============================
-- Loop principal
-- ===============================
while true do
    job_id = game.JobId
    if job_id ~= previous_job_id then
        previous_job_id = job_id
        last_sent_data = {}
    end

    if workspace and workspace:FindFirstChild("Plots") then
        scan_and_report()
    end

    task.wait(1)
    hop_next_available()
    task.wait(2)
end
