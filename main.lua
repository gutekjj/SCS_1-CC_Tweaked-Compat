-- main.lua
-- Reads config.json, opens a WebSocket to the configured port, sends "Ready:Gt" on connect.


local fs = fs
local function readConfig(path)
    if not fs or type(fs.exists) ~= "function" then return {} end
    local f = fs.open(path, "r")
    if not f then return {} end
    local content = f.readAll()
    f.close()
    local ok, cfg = pcall(textutils.unserializeJSON, content)
    return (ok and type(cfg) == "table") and cfg or {}
end

local function checkDetectors(ws, settings, detectors)
    print("Checking detectors...")
    for key, detector in pairs(detectors) do
        print("Checking detector: " .. key)
        print("Cable: " .. detector.kabel)
        local side = settings.stronaDetektorow or "bottom"
        local signal = redstone.testBundledInput(side, detector.kabel)
        local message = ""
        if signal == true then
            message = "z"
        else
            message = "w"
        end
        ws.send(key .. ":" .. message .. "\r\n")
    end
end

local function stringContains(haystack, needle)
    if haystack == nil or needle == nil then
        return false
    end
    return string.find(haystack, needle, 1, true) ~= nil
end

local function checkCrossings(ws, settings, crossings)
    print("Checking crossings...")
    for key, crossing in pairs(crossings) do
        print("Checking crossing: " .. key)
        local side = settings.stronaPrzejazdow or "top"
        local signalP = redstone.testBundledInput(side, crossing.RgPzamkniete)
        local signalL = redstone.testBundledInput(side, crossing.RgLzamkniete)
        if signalP then messageP = "_RgP:zamkniete" end
            
        if signalL then messageL = "_RgL:zamkniete" end
            
        if not signalP then messageP = "_RgP:otwarte" end

        if not signalL then messageL = "_RgL:otwarte" end

        ws.send(key .. messageP .. "\r\n")
        ws.send(key .. messageL .. "\r\n")
    end
end

local cfg = readConfig("config.json")
local settings = (type(cfg) == "table" and cfg.ustawienia) and cfg.ustawienia or {}
local port = settings.port or cfg.port or cfg.websocketPort or 8080
local host = settings.host or cfg.host or "localhost"
local secure = (settings["trybBezpieczny(WSS)"] or cfg["trybBezpieczny(WSS)"]) and true or false
local proto = secure and "wss" or "ws"
local url = proto .. "://" .. host .. ":" .. tostring(port)
local detectors = (type(cfg) == "table" and cfg.Detektory) and cfg.Detektory or {}
local przejazdy = (type(cfg) == "table" and cfg.przejazdy) and cfg.przejazdy or {}
local semafory = (type(cfg) == "table" and cfg.semafory) and cfg.semafory or {}
local zwrotnice = (type(cfg) == "table" and cfg.zwrotnice) and cfg.zwrotnice or {}
local tarcze = (type(cfg) == "table" and cfg.tarcze) and cfg.tarcze or {}

rs.setBundledOutput(settings.stronaPrzejazdow or "top", 0) -- Reset all outputs at start
rs.setBundledOutput(settings.stronaSemaforow or "left", 0)
rs.setBundledOutput(settings.stronaZwrotnic or "right", 0)
rs.setBundledOutput(settings.stronaTarcz or "top", 0)

local ws, error = http.websocket(url)
if ws then
    os.sleep(1) -- Wait a moment to ensure connection is established
    ws.send("Ready:" .. settings.skrotStacji .. "\r\n")
    os.sleep(0.5)
    checkDetectors(ws, settings, detectors)
    for i in pairs(przejazdy) do
        ws.send(przejazdy[i].name .. "_RgP:otwarte\r\n")
        os.sleep(0.2)
        ws.send(przejazdy[i].name .. "_RgL:otwarte\r\n")
        os.sleep(0.2)
        ws.send(przejazdy[i].name .. "_SD:otwarte\r\n")
    end
    checkDetectors(ws, settings, detectors)
    while true do
        local eventData = {os.pullEvent()}
        if eventData[1] == "websocket_message" and stringContains(tostring(eventData[3]), "GetState") then
            print("Received GetState command, checking detectors...")   
            checkDetectors(ws, settings, detectors)
            print("Message processed.")
        elseif eventData[1] == "websocket_message" and stringContains(tostring(eventData[3]), "zamykaj") then
            print("Received command: " .. tostring(eventData[3]))
            local currentCable = rs.getBundledOutput(settings.stronaPrzejazdow or "top")
            for i in pairs(przejazdy) do
                if stringContains(tostring(eventData[3]), przejazdy[i].name) then
                    if stringContains(tostring(eventData[3]), przejazdy[i].name .. "_RgP") then
                        rs.setBundledOutput(settings.stronaPrzejazdow or "top", colors.combine(currentCable, przejazdy[i].RgP))
                        print("Set " .. przejazdy[i].name .. "_RgP to zamkniete")
                        os.sleep(0.2)
                    elseif stringContains(tostring(eventData[3]), przejazdy[i].name .. "_RgL") then
                        currentCable = bit.bor(currentCable, przejazdy[i].RgL)
                        rs.setBundledOutput(settings.stronaPrzejazdow or "top", colors.combine(currentCable, przejazdy[i].RgL))
                        print("Set " .. przejazdy[i].name .. "_RgL to zamkniete")
                        os.sleep(0.2)
                    elseif stringContains(tostring(eventData[3]), przejazdy[i].name .. "_SD") then
                        currentCable = bit.bor(currentCable, przejazdy[i].SD)
                        rs.setBundledOutput(settings.stronaPrzejazdow or "top", colors.combine(currentCable, przejazdy[i].SD))
                        ws.send(przejazdy[i].name .. "_SD:zamkniete\r\n")
                        print("Set " .. przejazdy[i].name .. "_SD to zamkniete")
                        os.sleep(0.2)
                    end
                end
            end
        elseif eventData[1] == "websocket_message" and stringContains(tostring(eventData[3]), "otwieraj") then
            
            for i in pairs(przejazdy) do
                if stringContains(tostring(eventData[3]), przejazdy[i].name) then
                    local currentCable = rs.getBundledOutput(settings.stronaPrzejazdow or "top")
                    if stringContains(tostring(eventData[3]), przejazdy[i].name .. "_RgP") or stringContains(tostring(eventData[3]), przejazdy[i].name .. "_RgL") then
                        rs.setBundledOutput(settings.stronaPrzejazdow or "top", colors.subtract(currentCable, przejazdy[i].RgP, przejazdy[i].RgL))
                        print("Set " .. przejazdy[i].name .. "_RgP to otwarte")
                        os.sleep(0.2)

                        print("Set " .. przejazdy[i].name .. "_RgL to otwarte")
                        os.sleep(0.2)
                    end
    
                    if stringContains(tostring(eventData[3]), przejazdy[i].name .. "_SD") then
                        rs.setBundledOutput(settings.stronaPrzejazdow or "top", colors.subtract(currentCable, przejazdy[i].SD))
                        ws.send(przejazdy[i].name .. "_SD:otwarte\r\n")
                        print("Set " .. przejazdy[i].name .. "_SD to otwarte")
                        os.sleep(0.2)
                    end
                end
            end
        elseif eventData[1] == "websocket_message" and stringContains(tostring(eventData[3]), "-") or stringContains(tostring(eventData[3]), "+") then
            for i in pairs(zwrotnice) do
                if stringContains(tostring(eventData[3]), i) then
                    local currentCable = rs.getBundledOutput(settings.stronaZwrotnic or "right")
                    if stringContains(tostring(eventData[3]), i .. ":-") then
                        print("Setting zwrotnica " .. i .. " to -")
                        rs.setBundledOutput(settings.stronaZwrotnic or "right", colors.combine(currentCable, zwrotnice[i]))
                        print("Set zwrotnica " .. i .. " to -")
                        os.sleep(5)
                        ws.send(i .. ":-\r\n")
                        break
                    elseif stringContains(tostring(eventData[3]), i .. ":+") then
                        print("setting zwrotnica " .. i .. " to +")
                        rs.setBundledOutput(settings.stronaZwrotnic or "right", colors.subtract(currentCable, zwrotnice[i]))
                        print("Set zwrotnica " .. i .. " to +")
                        os.sleep(5)
                        ws.send(i .. ":+\r\n")
                        break
                    end
                end
            end
        elseif eventData[1] == "websocket_message" and stringContains(tostring(eventData[3]), "To") or stringContains(tostring(eventData[3]), "Tm") then
            print("Received tarcza command: " .. tostring(eventData[3]))
            for i in pairs(tarcze) do
                if stringContains(tostring(eventData[3]), i) then
                    local currentCable = rs.getBundledOutput(settings.stronaTarcz or "top")
                    print(i .. ":Ms2")
                    if stringContains(tostring(eventData[3]), i .. ":Ms2") then
                        local tarczaManewrowa = i
                        print("Setting tarcza: " .. tarczaManewrowa .. " to Ms2")
                        rs.setBundledOutput(settings.stronaTarcz or "top", colors.combine(currentCable, tarcze[tarczaManewrowa]))
                        print("Set tarcza: " .. tarczaManewrowa .. " to Ms2")
                        os.sleep(1)
                        ws.send(tarczaManewrowa .. ":Ms2\r\n")
                        break
                    elseif stringContains(tostring(eventData[3]), i .. ":Ms1") then
                        local tarczaManewrowa = i
                        print("Setting tarcza: " .. tarczaManewrowa .. " to Ms1")
                        rs.setBundledOutput(settings.stronaTarcz or "top", colors.subtract(currentCable, tarcze[tarczaManewrowa]))
                        print("Set tarcza: " .. tarczaManewrowa .. " to Ms1")
                        os.sleep(1)
                        ws.send(tarczaManewrowa .. ":Ms1\r\n")
                        break
                    elseif stringContains(tostring(eventData[3]), i .. ":Os1")then
                        local tarczaOstrzegawcza =  i
                        print("Setting tarcza: " .. tarczaOstrzegawcza .. " to Os1")
                        rs.setBundledOutput(settings.stronaTarcz or "top", colors.combine(currentCable, 0))
                        print("Set tarcza: " .. tarczaOstrzegawcza .. " to Os1")
                        os.sleep(1)
                        ws.send(tarczaOstrzegawcza .. ":Os1\r\n")
                        break
                    elseif stringContains(tostring(eventData[3]), i .. ":Os2")then
                        local tarczaOstrzegawcza = i
                        print("Setting tarcza: " .. tarczaOstrzegawcza .. " to Os2")
                        rs.setBundledOutput(settings.stronaTarcz or "top", colors.subtract(currentCable, tarcze[tarczaOstrzegawcza].Os2))
                        print("Set tarcza: " .. tarczaOstrzegawcza .. " to Os2")
                        os.sleep(1)
                        ws.send(tarczaOstrzegawcza .. ":Os2\r\n")
                        break
                    elseif stringContains(eventData[3], i .. ":Os3") then
                        local tarczaOstrzegawcza = i
                        print("Setting tarcza: " .. tarczaOstrzegawcza .. " to Os3")
                        
                        rs.setBundledOutput(settings.stronaTarcz or "top", colors.combine(currentCable, tarcze[tarczaOstrzegawcza].Os3))
                        print("Set tarcza: " .. tarczaOstrzegawcza .. " to Os3")
                        os.sleep(1)
                        ws.send(tarczaOstrzegawcza .. ":Os3\r\n")
                        break
                    elseif stringContains(eventData[3], i .. ":Os4") then
                        local tarczaOstrzegawcza = i
                        print("Setting tarcza: " .. tarczaOstrzegawcza .. " to Os4")
                        rs.setBundledOutput(settings.stronaTarcz or "top", colors.subtract(currentCable, tarcze[tarczaOstrzegawcza].Os4))
                        print(tarcze[tarczaOstrzegawcza].Os4)
                        print("Set tarcza: " .. tarczaOstrzegawcza .. " to Os4")
                        os.sleep(1)
                        ws.send(tarczaOstrzegawcza .. ":Os4\r\n")
                        break
                    end
                end
            end
        elseif eventData[1] == "websocket_message" and stringContains(tostring(eventData[3]), "S") then
            for i in pairs(semafory) do
                if stringContains(tostring(eventData[3]), i) then
                    local currentCable = rs.getBundledOutput(settings.stronaSemaforow or "left")
                    for signal, cable in pairs(semafory[i]) do
                        if stringContains(tostring(eventData[3]), i .. ":" .. signal) then
                            print("Setting semafor: " .. i .. " to " .. signal)
                            rs.setBundledOutput(settings.stronaSemaforow or "left", colors.combine(currentCable, cable))
                            print("Set semafor: " .. i .. " to " .. signal)
                            os.sleep(1)
                            ws.send(i .. ":" .. signal .. "\r\n")
                            break
                        elseif stringContains(tostring(eventData[3]), i .. ":S1") then
                            print("Setting semafor: " .. i .. " to S1")
                            rs.setBundledOutput(settings.stronaSemaforow or "left", 0)
                            print("Set semafor: " .. i .. " to S1")
                            os.sleep(1)
                            ws.send(i .. ":S1\r\n")
                            break
                        end
                    end
                end
            end
        elseif eventData[1] == "redstone" then
            print("Redstone event detected, checking detectors...")
            checkDetectors(ws, settings, detectors)
            checkCrossings(ws, settings, przejazdy)
            print("Redstone event processed.")
        end

    end
else
    print("Failed to connect to WebSocket: " .. tostring(error))
end