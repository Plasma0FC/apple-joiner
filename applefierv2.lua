-- ✅ ✅ ✅ SUPREMO FINDER + SERVER HOPPER COMPLETO ✅ ✅ ✅
-- Place ID já configurado para: 109983668079237

-----------------------------------------------------------------------
-- CONFIGURAÇÃO
-----------------------------------------------------------------------
local PLACE_ID = 109983668079237
local DEBUG = false
local INSTANCE_RANDOM_DELAY_MAX = 0.35
local FETCH_LIMIT = 120
local POOL_TARGET_MIN = 80
local POOL_REFRESH_COOLDOWN = 5
local SCAN_TIMEOUT = 3
local MAX_SCAN_ITEMS = 150
local MIN_PPS = 1000000
local HOP_DELAY_ON_FAILURE = 0.5
local GLOBAL_POOL_LIMIT = 2000
local MAX_ATTEMPTS_PER_ID = 2
local TELEPORT_ATTEMPT_COOLDOWN = 1.5
local JOIN_LINK_TEMPLATE = "roblox://placeId=%s&gameInstanceId=%s"
local TINYURL_API_TOKEN = nil

local WEBHOOK_VERYLOW = "https://discord.com/api/webhooks/1402772636013953155/nT3OVpiEC1w5uyn6KHzC-1FLf2-bOwlpKSD1oCvb1t-x0VeaNA5I-zS5WBRgdPY0GjuW"
local WEBHOOK_LOW     = "https://discord.com/api/webhooks/1402772636013953155/nT3OVpiEC1w5uyn6KHzC-1FLf2-bOwlpKSD1oCvb1t-x0VeaNA5I-zS5WBRgdPY0GjuW"
local WEBHOOK_MID     = "https://discord.com/api/webhooks/1402772636013953155/nT3OVpiEC1w5uyn6KHzC-1FLf2-bOwlpKSD1oCvb1t-x0VeaNA5I-zS5WBRgdPY0GjuW"
local WEBHOOK_HIGH    = "https://discord.com/api/webhooks/1402772636013953155/nT3OVpiEC1w5uyn6KHzC-1FLf2-bOwlpKSD1oCvb1t-x0VeaNA5I-zS5WBRgdPY0GjuW"
local WEBHOOK_ULTRA   = "https://discord.com/api/webhooks/1402772636013953155/nT3OVpiEC1w5uyn6KHzC-1FLf2-bOwlpKSD1oCvb1t-x0VeaNA5I-zS5WBRgdPY0GjuW"
local WEBHOOK_CLUTCH  = "https://discord.com/api/webhooks/1402772636013953155/nT3OVpiEC1w5uyn6KHzC-1FLf2-bOwlpKSD1oCvb1t-x0VeaNA5I-zS5WBRgdPY0GjuW"

local EMBED_USERNAME = "Supremo Finder"
local EMBED_COLOR = 10181046

local PRIORITY_NAMES = {
    'Strawberry Elephant',
    'Dragon Cannelloni',
    'Garama and Madundung',
    'La Supreme Combinasion',
    'La Secret Combinasion',
    'Ketchuru and Musturu',
    'Tictac Sahur',
    'Tang Tang Keletang',
    'Tralaledon',
    'Nuclearo Dinossauro',
    'Ketupat Kepat',
    'Spaghetti Tualetti',
}

-----------------------------------------------------------------------
-- INÍCIO DO CÓDIGO (não alterar)
-----------------------------------------------------------------------
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local ROOT_PLOTS = workspace:FindFirstChild("Plots") or workspace

local t_wait = task.wait
local t_spawn = task.spawn
local now = os.clock

local function log(...)
    if DEBUG then print("[SUPREMO]", ...) end
end

local function safe_env()
    local ok, g = pcall(function() return getgenv() end)
    if ok and type(g) == "table" then return g end
    if type(shared)=="table" then shared.__SUPREMO_ENV = shared.__SUPREMO_ENV or {}; return shared.__SUPREMO_ENV end
    if type(_G)=="table" then _G.__SUPREMO_ENV = _G.__SUPREMO_ENV or {}; return _G.__SUPREMO_ENV end
    return {}
end

local ENV=safe_env()
if ENV.__SUPREMO_RUNNING then warn("Já rodando");return end
ENV.__SUPREMO_RUNNING=true

local function detect_request_func()
    if syn and syn.request then return syn.request end
    if http_request then return http_request end
    if request then return request end
    if http and http.request then return http.request end
end
local request_func=detect_request_func()

local last_request_time=0
local function throttled_wait(minimum)
    minimum=minimum or 0.25
    local e=os.clock()-last_request_time
    if e<minimum then t_wait(minimum-e) end
    last_request_time=os.clock()
end

local function http_get(url,a)
    a=a or 1
    throttled_wait(0.25)
    if request_func then
        local ok,res=pcall(function()
            return request_func({Url=url,Method="GET",Headers={["Accept"]="application/json"}})
        end)
        if not ok or not res then if a<3 then t_wait(1) return http_get(url,a+1) end return 0,"" end
        local code=res.StatusCode or res.Status or 0
        local body=res.Body or res.body or""
        if code==429 then if a<4 then t_wait(2*a) return http_get(url,a+1) end return 429,"" end
        return code,tostring(body)
    else
        local ok,body=pcall(function() return game:HttpGet(url,true) end)
        return ok and 200 or 0,body or""
    end
end

local function http_post_json(url,tbl)
    throttled_wait(0.3)
    if not request_func then return false end
    local ok,res=pcall(function()
        return request_func({
            Url=url,Method="POST",
            Headers={["Content-Type"]="application/json"},
            Body=HttpService:JSONEncode(tbl or{})
        })
    end)
    if not ok or not res then return false end
    local c=res.StatusCode or res.Status or 0
    return c>=200 and c<300
end

local function short_link(u)
    if not TINYURL_API_TOKEN then return u end return u
end

ENV.__SUPREMO_POOL=ENV.__SUPREMO_POOL or{}
ENV.__SUPREMO_POOL_LOCK=ENV.__SUPREMO_POOL_LOCK or{last=0,refreshing=false}
ENV.__SUPREMO_POSTED=ENV.__SUPREMO_POSTED or{}
ENV.__SUPREMO_USED_IDS=ENV.__SUPREMO_USED_IDS or{}
ENV.__SUPREMO_ID_ATTEMPTS=ENV.__SUPREMO_ID_ATTEMPTS or{}


local function pool_try_lock()
    if ENV.__SUPREMO_POOL_LOCK.refreshing then return false end
    local age=os.clock()-(ENV.__SUPREMO_POOL_LOCK.last or 0)
    if age<POOL_REFRESH_COOLDOWN then return false end
    ENV.__SUPREMO_POOL_LOCK.refreshing=true
    ENV.__SUPREMO_POOL_LOCK.last=os.clock()
    return true
end

local function pool_unlock() ENV.__SUPREMO_POOL_LOCK.refreshing=false end

local function build_servers_url(pid,limit,cursor)
    local base=("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=%d"):format(pid,limit or FETCH_LIMIT)
    if cursor then base=base.."&cursor="..cursor end return base
end

local function fetch_servers_once()
    local ids={}
    local url=build_servers_url(PLACE_ID,FETCH_LIMIT)
    local code,body=http_get(url)
    if code~=200 then return{}end
    local ok,p=pcall(HttpService.JSONDecode,HttpService,body)
    if not ok or not p or not p.data then return{}end
    for _,s in ipairs(p.data) do
        local id=tostring(s.id)
        local pl=tonumber(s.playing)or 0
        local mx=tonumber(s.maxPlayers)or 8
        if id~=tostring(game.JobId) and pl>=1 and pl<mx then
            table.insert(ids,id)
        end
    end
    return ids
end

local function refresh_pool_once()
    if not pool_try_lock()then return false end
    local ids=fetch_servers_once()
    for i=#ids,2,-1 do local j=math.random(i) ids[i],ids[j]=ids[j],ids[i] end
    local pool=ENV.__SUPREMO_POOL
    local exist={}
    for _,v in ipairs(pool) do exist[v]=true end
    for _,id in ipairs(ids) do
        if not exist[id] and not ENV.__SUPREMO_USED_IDS[id] and #pool<GLOBAL_POOL_LIMIT then
            table.insert(pool,id)
        end
    end
    pool_unlock()
end

local function ensure_pool()
    if #ENV.__SUPREMO_POOL<POOL_TARGET_MIN then t_spawn(refresh_pool_once) end
end

local function get_random_from_pool()
    local pool=ENV.__SUPREMO_POOL
    if #pool==0 then return nil end
    local i=math.random(#pool)
    return table.remove(pool,i)
end

local suffixMul={K=1e3,M=1e6,B=1e9,T=1e12}
local function parsePps(t)
    if not t then return nil end
    local s=t:gsub("%$",""):gsub("/s",""):gsub("%s+","")
    local n,suf=s:match("([%d%.]+)([KkMmBbTt]?)")
    n=tonumber(n)if not n then return nil end
    if suf~=""then n=n*(suffixMul[suf:upper()]or 1) end
    return n
end
local function human(n)
    if n>=1e12 then return("%.2fT"):format(n/1e12)end
    if n>=1e9 then return("%.2fB"):format(n/1e9)end
    if n>=1e6 then return("%.2fM"):format(n/1e6)end
    if n>=1e3 then return("%.2fk"):format(n/1e3)end
    return tostring(math.floor(n))
end

local PRIORITY_MAP={}
local PRIORITY_SET={}
for i,n in ipairs(PRIORITY_NAMES)do PRIORITY_MAP[n:lower()]=i PRIORITY_SET[n:lower()]=true end

local function safeFind(p,n,r)
    local ok,res=pcall(function()return p:FindFirstChild(n,r)end)
    return ok and res or nil
end
local function safeGetText(o)
    if not o then return nil end local ok,t=pcall(function()return o.Text or o.Value end)
    return ok and t or nil
end
local function findPerSecondText(o)
    local f={"Generation","ValuePerSecond","GPS","MoneyPerSecond"}
    for _,n in ipairs(f)do local g=safeFind(o,n,true)local t=safeGetText(g)if t and t:find("/s")then return t end end
end

local function resolveMutation(o)
    local m=safeFind(o,"Mutation",true)
    local t=safeGetText(m)if not t then return"Normal"end return t:gsub("<.->","")
end
local function getDisplayName(o)
    return safeGetText(safeFind(o,"DisplayName",true))or""
end

local function getPlotRoot(o)
    local p=o
    while p and p.Parent do if p.Parent==ROOT_PLOTS then return p end p=p.Parent end
end

local function getBaseOwner(root)
    if not root then return"Unknown"end
    local s=safeFind(root,"PlotSign",true)
    local sg=safeFind(s,"SurfaceGui",true)
    if sg then
        for _,d in ipairs(sg:GetDescendants())do
            if d:IsA("TextLabel")then
                local t=safeGetText(d)
                if t then local o=t:match("^(.-)%s*'s")if o then return o end end
            end
        end
    end
    return"Unknown"
end

local function collectAllRows()
    local rows={}local st=os.clock()
    local ok,desc=pcall(function()return ROOT_PLOTS:GetDescendants()end)if not ok then return rows end
    local c=0
    for _,d in ipairs(desc)do
        if os.clock()-st>SCAN_TIMEOUT or c>=MAX_SCAN_ITEMS then break end
        if d.Name=="AnimalOverhead"then
            c+=1
            local root=getPlotRoot(d)
            local base=getBaseOwner(root)
            local disp=getDisplayName(d)
            local mut=resolveMutation(d)
            local t=findPerSecondText(d)
            local n=parsePps(t)or 0
            if n>=MIN_PPS and disp~=""then
                local rank=PRIORITY_MAP[disp:lower()]or math.huge
                table.insert(rows,{base=base,display=disp,mutation=mut,perSecond=n,priRank=rank,isPriority=rank~=math.huge})
            end
        end
    end
    return rows
end

local function pickBest(r)
    local b,br=nil,math.huge
    for _,v in ipairs(r)do if v.isPriority and v.priRank<br then b=v;br=v.priRank end end
    if not b then for _,v in ipairs(r)do if not b or v.perSecond>b.perSecond then b=v end end end
    return b
end

local function groupByBase(r)
    local g,order={},{}
    for _,v in ipairs(r)do
        if not g[v.base]then g[v.base]={base=v.base,items={},best=v.perSecond}order[#order+1]=v.base end
        table.insert(g[v.base].items,{mutation=v.mutation,display=v.display,perSecond=v.perSecond})
        if v.perSecond>g[v.base].best then g[v.base].best=v.perSecond end
    end
    for _,b in ipairs(order)do table.sort(g[b].items,function(a,b)return a.perSecond>b.perSecond end)end
    table.sort(order,function(a,b)return g[a].best>g[b].best end)
    local arr={}for _,b in ipairs(order)do arr[#arr+1]=g[b]end return arr
end

local ONE_M, TEN_M, FIFTY_M, HUND_M, FIVEH_M =1e6,1e7,5e7,1e8,5e8
local function choose_tier_hook(v)
    if v>=FIVEH_M then return WEBHOOK_ULTRA,FIVEH_M end
    if v>=HUND_M then return WEBHOOK_HIGH,HUND_M end
    if v>=FIFTY_M then return WEBHOOK_MID,FIFTY_M end
    if v>=TEN_M then return WEBHOOK_LOW,TEN_M end
    if v>=ONE_M then return WEBHOOK_VERYLOW,ONE_M end
end

local function already_posted(job,hook) return ENV.__SUPREMO_POSTED[job.."|"..hook] end
local function mark_posted(job,hook) ENV.__SUPREMO_POSTED[job.."|"..hook]=true end

local function wikiThumb(n)
    local safe=n:gsub("[^%w%s]"," "):gsub("%s+","-")
    return("https://steal-a-brainrot.wiki/wp-content/uploads/2025/07/%s.png"):format(safe)
end

local function humanGroups(g,l)
    local b={}
    for _,gr in ipairs(g)do
        local lines={}
        for _,it in ipairs(gr.items)do if it.perSecond>=l then lines[#lines+1]=("• %s - %s ($%s/s)"):format(it.mutation,it.display,human(it.perSecond))end end
        if #lines>0 then b[#b+1]="Base: "..gr.base b[#b+1]=table.concat(lines,"\n") end
    end
    return table.concat(b,"\n\n")
end

local function humanClutch(g)
    local b={}
    for _,gr in ipairs(g)do local lines={}for _,it in ipairs(gr.items)do if it.perSecond>=FIFTY_M or PRIORITY_SET[it.display:lower()]then lines[#lines+1]=("• %s - %s ($%s/s)"):format(it.mutation,it.display,human(it.perSecond))end end if#lines>0 then b[#b+1]="Base: "..gr.base b[#b+1]=table.concat(lines,"\n")end end
    return table.concat(b,"\n\n")
end

local function post_webhooks(best,grouped)
    if not best then return end
    local v=best.perSecond
    local job=tostring(game.JobId)
    local hook,lb=choose_tier_hook(v)
    if hook and not already_posted(job,hook)then
        t_spawn(function()
            local pay={
                username=EMBED_USERNAME,
                embeds={{title="Finder",description=("**Best:** %s - %s ($%s/s)\nPlayers: %d/8"):format(best.mutation,best.display,human(v),#Players:GetPlayers()),color=EMBED_COLOR,thumbnail={url=wikiThumb(best.display)},fields={{name="Job ID",value="```"..job.."```"},{name="Brainrots",value=humanGroups(grouped,lb)}},timestamp=os.date("!%Y-%m-%dT%H:%M:%SZ")}}
            }
            if http_post_json(hook,pay)then mark_posted(job,hook)end
        end)
    end

    local clutch=humanClutch(grouped)
    if clutch~=""and not already_posted(job,WEBHOOK_CLUTCH)then
        t_spawn(function()
            local pay={
                username=EMBED_USERNAME,
                embeds={{title="CLUTCH ⚡",description=("Player Count: %d\n\n%s"):format(#Players:GetPlayers(),clutch),color=EMBED_COLOR,timestamp=os.date("!%Y-%m-%dT%H:%M:%SZ")}}
            }
            if http_post_json(WEBHOOK_CLUTCH,pay)then mark_posted(job,WEBHOOK_CLUTCH)end
        end)
    end
end

-----------------------------------------------------------------------
-- TELEPORT / HOP LOOP
-----------------------------------------------------------------------
local function hopTo(id)
    local tries=ENV.__SUPREMO_ID_ATTEMPTS[id]or 0
    if tries>=MAX_ATTEMPTS_PER_ID then return false end
    ENV.__SUPREMO_ID_ATTEMPTS[id]=tries+1
    local ok=pcall(function() TeleportService:TeleportToPlaceInstance(PLACE_ID,id,Players.LocalPlayer) end)
    return ok
end

task.wait(math.random())