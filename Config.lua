local HttpService = game:GetService("HttpService")
local SaveManager = {}

SaveManager.Folder = "ICSW/Default"
SaveManager.Ignore = {}
SaveManager.WindUI = nil
SaveManager._cache = {}
SaveManager._lastRefresh = 0

SaveManager.Parser = {
    Toggle = {
        Save = function(idx, object) 
            local keybindValue = nil 
            local keybindMode = nil 
            if object.Keybind then 
                keybindValue = object.Keybind.Value or object.Keybind.Default 
                keybindMode = object.Keybind.Mode or "Toggle" 
            end 
            return { type = "Toggle", idx = idx, value = object.Value, key = keybindValue, mode = keybindMode } 
        end,
        Load = function(idx, data) 
            if SaveManager.Library.Options[idx] then 
                SaveManager.Library.Options[idx]:SetValue(data.value) 
                if data.key and SaveManager.Library.Options[idx].Keybind then 
                    SaveManager.Library.Options[idx].Keybind:SetValue(data.key, data.mode or "Toggle") 
                end 
            end 
        end,
    },
    
    Slider = {
        Save = function(idx, object) 
            return { type = "Slider", idx = idx, value = tostring(object.Value) } 
        end,
        Load = function(idx, data) 
            if SaveManager.Library.Options[idx] then 
                SaveManager.Library.Options[idx]:SetValue(data.value)
            end 
        end,
    },
    
    Dropdown = {
        Save = function(idx, object) 
            return { type = "Dropdown", idx = idx, value = object.Value, multi = object.Multi } 
        end,
        Load = function(idx, data) 
            if SaveManager.Library.Options[idx] then 
                SaveManager.Library.Options[idx]:SetValue(data.value) 
            end 
        end,
    },
    
    Colorpicker = {
        Save = function(idx, object) 
            return { 
                type = "Colorpicker", 
                idx = idx, 
                value = object.Value:ToHex(), 
                transparency = object.Transparency 
            } 
        end,
        Load = function(idx, data) 
            if SaveManager.Library.Options[idx] then 
                if data.value and data.transparency ~= nil then
                    local success = pcall(function()
                        SaveManager.Library.Options[idx]:SetValueRGB(Color3.fromHex(data.value), data.transparency) 
                    end)
                end
            end 
        end,
    },
    
    Keybind = {
        Save = function(idx, object) 
            return { type = "Keybind", idx = idx, mode = object.Mode, key = object.Value } 
        end,
        Load = function(idx, data) 
            if SaveManager.Library.Options[idx] then 
                SaveManager.Library.Options[idx]:SetValue(data.key, data.mode) 
            end 
        end,
    },
    
    Input = {
        Save = function(idx, object) 
            return { type = "Input", idx = idx, text = object.Value } 
        end,
        Load = function(idx, data) 
            if SaveManager.Library.Options[idx] and type(data.text) == "string" then 
                SaveManager.Library.Options[idx]:SetValue(data.text) 
            end 
        end,
    },
}

function SaveManager:SetLibrary(library, windui)
    self.Library = library
    self.WindUI = windui or getgenv().WindUI_Notification
end

function SaveManager:IgnoreThemeSettings()
    self:SetIgnoreIndexes({ "InterfaceTheme", "InterfaceAcrylic", "InterfaceTransparency", "MinimizeKeyBind" })
end

function SaveManager:SetIgnoreIndexes(list)
    for _, key in pairs(list) do 
        self.Ignore[key] = true 
    end
end

function SaveManager:SetFolder(folder)
    self.Folder = folder
    self:BuildFolderTree()
end

SaveManager.FoldersCreated = false
function SaveManager:BuildFolderTree()
    if self.FoldersCreated then return end
    
    local success = pcall(function()
        local paths = {
            self.Folder,
            self.Folder .. "/settings",
            self.Folder .. "/autoload"
        }

        for _, p in pairs(paths) do
            if not isfolder(p) then 
                makefolder(p) 
            end
        end
    end)
    
    if success then
        self.FoldersCreated = true
    end
end

function SaveManager:RefreshConfigList()
    if tick() - self._lastRefresh < 1 and self._cache and #self._cache > 0 then
        return self._cache
    end
    
    if not self.FoldersCreated then 
        self:BuildFolderTree() 
    end
    
    local success, list = pcall(listfiles, self.Folder .. "/settings")
    if not success then 
        self._cache = {}
        return {} 
    end
    
    local out = {}
    local currentDefaultName = "Default_" .. tostring(game.PlaceId)
    local maxFiles = 100

    for i, file in pairs(list) do
        if i > maxFiles then break end
        
        local name = file:match("settings/([^/]+)%.json$") or file:match("settings\\([^\\]+)%.json$")
        if name then
            if name == currentDefaultName then
                table.insert(out, "Default")
            else
                local readSuccess, content = pcall(readfile, file)
                if readSuccess and type(content) == "string" and #content > 0 and #content < 500000 then
                    local decodeSuccess, data = pcall(HttpService.JSONDecode, HttpService, content)
                    if decodeSuccess and type(data) == "table" then
                        if not data.PlaceId or data.PlaceId == game.PlaceId then
                            table.insert(out, name)
                        end
                    end
                end
            end
        end
    end
    
    self._cache = out
    self._lastRefresh = tick()
    return out
end

function SaveManager:ResolveName(name)
    if name == "Default" then
        return "Default_" .. tostring(game.PlaceId)
    end
    return name
end

function SaveManager:Save(name)
    if not name or name == "" then 
        return false, "No Config Name" 
    end
    
    if name == "Default" then
        return false, "Cannot save as Default"
    end
    
    local realName = self:ResolveName(name)
    self:BuildFolderTree()
    local fullPath = self.Folder .. "/settings/" .. realName .. ".json"
    
    local data = { 
        objects = {}, 
        PlaceId = game.PlaceId,
        SavedAt = tick()
    }
    
    local options = self.Library.Options
    local ignore = self.Ignore
    local parser = self.Parser
    
    for idx, option in pairs(options) do
        if not ignore[idx] then
            local optionType = option.Type
            if parser[optionType] then
                local success, result = pcall(parser[optionType].Save, idx, option)
                if success and result then
                    data.objects[idx] = result
                end
            end
        end
    end
    
    if options.InterfaceTheme then 
        data.Theme = options.InterfaceTheme.Value 
    end
    if options.MinimizeKeyBind then 
        data.MinimizeKey = options.MinimizeKeyBind.Value 
    end

    local success, encoded = pcall(HttpService.JSONEncode, HttpService, data)
    if not success then 
        return false, "Encoding Failed" 
    end
    
    local writeSuccess = pcall(writefile, fullPath, encoded)
    if writeSuccess then
        self._lastRefresh = 0
    end
    
    return writeSuccess
end

function SaveManager:Load(name)
    if not name or name == "" then 
        return false, "No Config Selected" 
    end
    
    local realName = self:ResolveName(name)
    local fullPath = self.Folder .. "/settings/" .. realName .. ".json"
    
    if not isfile(fullPath) then 
        return false, "Config Not Found"
    end
    
    local readSuccess, content = pcall(readfile, fullPath)
    if not readSuccess or not content or #content == 0 then 
        return false, "Failed to read file"
    end
    
    local decodeSuccess, decoded = pcall(HttpService.JSONDecode, HttpService, content)
    if not decodeSuccess or type(decoded) ~= "table" then 
        return false, "Invalid Config Format"
    end
    
    if decoded.PlaceId and decoded.PlaceId ~= game.PlaceId then
        if self.WindUI then 
            self.WindUI:Notify({
                Title = "Config", 
                Content = "PlaceId Mismatch", 
                Duration = 5, 
                Icon = "rbxassetid://17368208554"
            }) 
        end
        return false, "PlaceId Mismatch"
    end
    
    local parser = self.Parser
    if decoded.objects and type(decoded.objects) == "table" then
        for _, option in pairs(decoded.objects) do
            if option and option.type and option.type ~= "Toggle" and parser[option.type] then
                pcall(parser[option.type].Load, option.idx, option)
            end
        end
        
        for _, option in pairs(decoded.objects) do
            if option and option.type == "Toggle" and parser[option.type] then
                pcall(parser[option.type].Load, option.idx, option)
            end
        end
    end

    local options = self.Library.Options
    if decoded.Theme and options.InterfaceTheme then 
        pcall(function() 
            options.InterfaceTheme:SetValue(decoded.Theme) 
        end)
    end
    if decoded.MinimizeKey and options.MinimizeKeyBind then 
        pcall(function() 
            options.MinimizeKeyBind:SetValue(decoded.MinimizeKey) 
        end)
    end

    return true
end

function SaveManager:Delete(name)
    if not name or name == "" then 
        return false, "No Config Selected" 
    end
    
    if name == "Default" then
        return false, "Cannot Delete Default"
    end
    
    local realName = self:ResolveName(name)
    local fullPath = self.Folder .. "/settings/" .. realName .. ".json"
    
    if isfile(fullPath) then 
        local success = pcall(delfile, fullPath)
        if success then
            self._lastRefresh = 0
        end
        return success
    end
    
    return true
end

function SaveManager:GetAutoloadPath()
    return self.Folder .. "/autoload/" .. tostring(game.PlaceId) .. ".txt"
end

function SaveManager:GetCurrentAutoloadName()
    local path = self:GetAutoloadPath()
    if isfile(path) then
        local success, content = pcall(readfile, path)
        if success and content then
            local name = content:gsub("^%s*(.-)%s*$", "%1")
            if name ~= "" then 
                return name 
            end
        end
    end
    return "None"
end

function SaveManager:SetAutoload(name)
    if not name or name == "" then return false end
    local success = pcall(writefile, self:GetAutoloadPath(), name)
    return success
end

function SaveManager:LoadAutoloadConfig()
    local path = self:GetAutoloadPath()
    if isfile(path) then
        local success, content = pcall(readfile, path)
        if success and content then
            local name = content:gsub("^%s*(.-)%s*$", "%1")
            if name ~= "" then
                self:Load(name)
                return name
            end
        end
    end
    return nil
end

function SaveManager:CheckDefaultConfig()
    self:BuildFolderTree()
    
    local oldDefault = self.Folder .. "/settings/Default.json"
    if isfile(oldDefault) then 
        pcall(delfile, oldDefault) 
    end

    local name = "Default_" .. tostring(game.PlaceId) 
    local fullPath = self.Folder .. "/settings/" .. name .. ".json"
    
    local data = { 
        objects = {}, 
        PlaceId = game.PlaceId,
        CreatedAt = tick()
    }
    
    local options = self.Library.Options
    local ignore = self.Ignore
    local parser = self.Parser
    
    for idx, option in pairs(options) do
        if not ignore[idx] then
            local optionType = option.Type
            if parser[optionType] then
                local success, result = pcall(parser[optionType].Save, idx, option)
                if success and result then
                    data.objects[idx] = result
                end
            end
        end
    end
    
    if options.InterfaceTheme then 
        data.Theme = options.InterfaceTheme.Value 
    end
    if options.MinimizeKeyBind then 
        data.MinimizeKey = options.MinimizeKeyBind.Value 
    end

    local success, encoded = pcall(HttpService.JSONEncode, HttpService, data)
    if success and encoded then
        pcall(writefile, fullPath, encoded)
    end
end

function SaveManager:BuildConfigSection(tab)
    self:BuildFolderTree()

        if self.Library and not self.Library.Options["MinimizeKeyBind"] then
        local interfaceSection = tab:AddSection("Interface")
        
        interfaceSection:AddKeybind("MinimizeKeyBind", {
            Title = "Minimize Key",
            Description = "Hide UI",
            Default = "LeftAlt",
            ChangedCallback = function(NewKey)
                if self.Library then
                    self.Library.MinimizeKey = NewKey
                end
            end
        })
    end

    local section = tab:AddSection("Configuration")
    
    local AutoloadButton 

    local ConfigDropdown = section:AddDropdown("SaveManager_ConfigList", {
        Title = "List",
        Values = self:RefreshConfigList(),
        Multi = false,
    })
    
    section:AddInput("SaveManager_ConfigName", {
        Title = "Name",
        Placeholder = "Enter Name...",
        Callback = function() end
    })
    
    section:AddButton({
        Title = "Create",
        Callback = function()
            local name = self.Library.Options.SaveManager_ConfigName.Value
            if not name or name:gsub(" ", "") == "" then return end
            
            if name == "Default" then
                if self.WindUI then 
                    self.WindUI:Notify({
                        Title = "Error", 
                        Content = "Cannot Create Default", 
                        Duration = 3, 
                        Icon = "rbxassetid://17368208554"
                    }) 
                end
                return
            end
            
            local success = self:Save(name)
            
            if success then
                task.delay(0.1, function()
                    ConfigDropdown:SetValues(self:RefreshConfigList())
                    ConfigDropdown:SetValue(nil)
                end)
                
                if self.WindUI then 
                    self.WindUI:Notify({
                        Title = "Config", 
                        Content = "Created: " .. name, 
                        Duration = 3, 
                        Icon = "rbxassetid://17368190066"
                    }) 
                end
            end
        end
    })
    
    section:AddButton({
        Title = "Load",
        Callback = function()
            local name = ConfigDropdown.Value
            if not name then return end
            
            local success = self:Load(name)
            
            if success and self.WindUI then 
                self.WindUI:Notify({
                    Title = "Config", 
                    Content = "Loaded: " .. name, 
                    Duration = 3, 
                    Icon = "rbxassetid://17368190066"
                }) 
            end
        end
    })
    
    section:AddButton({
        Title = "Overwrite",
        Callback = function()
            local name = ConfigDropdown.Value
            if not name then return end
            
            if name == "Default" then
                if self.WindUI then 
                    self.WindUI:Notify({
                        Title = "Error", 
                        Content = "Cannot Overwrite Default", 
                        Duration = 3, 
                        Icon = "rbxassetid://17368208554"
                    }) 
                end
                return
            end
            
            local success = self:Save(name)
            
            if success and self.WindUI then 
                self.WindUI:Notify({
                    Title = "Config", 
                    Content = "Overwritten: " .. name, 
                    Duration = 3, 
                    Icon = "rbxassetid://17368190066"
                }) 
            end
        end
    })
    
    section:AddButton({
        Title = "Delete",
        Callback = function()
            local name = ConfigDropdown.Value
            if not name then return end
            
            if name == "Default" then
                if self.WindUI then 
                    self.WindUI:Notify({
                        Title = "Error", 
                        Content = "Cannot Delete Default", 
                        Duration = 3, 
                        Icon = "rbxassetid://17368208554"
                    }) 
                end
                return
            end
            
            local currentAutoload = self:GetCurrentAutoloadName()
            if name == currentAutoload then
                local autoloadPath = self:GetAutoloadPath()
                if isfile(autoloadPath) then 
                    pcall(delfile, autoloadPath) 
                end
                if AutoloadButton then 
                    AutoloadButton:SetDesc("Current: None") 
                end
            end
            
            local success = self:Delete(name)
            
            if success then
                task.delay(0.1, function()
                    ConfigDropdown:SetValues(self:RefreshConfigList())
                    ConfigDropdown:SetValue(nil)
                end)
                
                if self.WindUI then 
                    self.WindUI:Notify({
                        Title = "Config", 
                        Content = "Deleted: " .. name, 
                        Duration = 3, 
                        Icon = "rbxassetid://17368190066"
                    }) 
                end
            end
        end
    })

    AutoloadButton = section:AddButton({
        Title = "Set as Autoload",
        Description = "Current: " .. self:GetCurrentAutoloadName(),
        Callback = function()
            local name = ConfigDropdown.Value
            if not name then return end
            
            if name == "Default" then
                if self.WindUI then 
                    self.WindUI:Notify({
                        Title = "Error", 
                        Content = "Cannot Autoload Default", 
                        Duration = 3, 
                        Icon = "rbxassetid://17368208554"
                    }) 
                end
                return
            end
            
            local success = self:SetAutoload(name)
            
            if success then
                AutoloadButton:SetDesc("Current: " .. name)
                
                if self.WindUI then 
                    self.WindUI:Notify({
                        Title = "Autoload", 
                        Content = "Set: " .. name, 
                        Duration = 3, 
                        Icon = "rbxassetid://17368190066"
                    }) 
                end
            end
        end
    })
    
    section:AddButton({
        Title = "Clear Autoload",
        Callback = function()
            local path = self:GetAutoloadPath()
            if isfile(path) then 
                pcall(delfile, path) 
            end
            
            AutoloadButton:SetDesc("Current: None")
        end
    })
end

-- ================================================================
-- Mics Tab (Engine + UI)
-- ================================================================
function SaveManager:BuildMiscSection(tab)
    local Players = game:GetService("Players")
    local LP = Players.LocalPlayer
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")

    getgenv().ICSW_ESPEnabled = false
    getgenv().ICSW_ESPColor = Color3.fromRGB(255, 182, 211)
    getgenv().ICSW_ESPInstances = getgenv().ICSW_ESPInstances or {}
    getgenv().ICSW_WalkEnabled = false
    getgenv().ICSW_OriginalWalkSpeed = 16
    getgenv().ICSW_WalkSpeed = 50
    getgenv().ICSW_InfJumpEnabled = false
    getgenv().ICSW_FlyEnabled = false
    getgenv().ICSW_FlySpeed = 50
    getgenv().ICSW_NoclipEnabled = false
    getgenv().ICSW_SpectateTarget = ""
    getgenv().ICSW_AntiAdminEnabled = false

    -- ================================================================
    -- [Engine] Speed Hook
    -- ================================================================
    if not getgenv().ICSW_WalkSpeedHook then
        getgenv().ICSW_WalkSpeedHook = true
        local oldIndex
        oldIndex = hookmetamethod(game, "__index", function(self, key)
            if not checkcaller() and self:IsA("Humanoid") and key == "WalkSpeed" then
                return 16
            end
            return oldIndex(self, key)
        end)
    end

    -- ================================================================
    -- [Engine] Player (Walk, Jump, Fly, Noclip)
    -- ================================================================
    if getgenv().ICSW_PlayerLoop then getgenv().ICSW_PlayerLoop:Disconnect() end
    getgenv().ICSW_PlayerLoop = RunService.RenderStepped:Connect(function()
        local char = LP.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChild("Humanoid")

        if char and hrp and hum then
            if getgenv().ICSW_WalkEnabled then
                hum.WalkSpeed = getgenv().ICSW_WalkSpeed
            end

            local flyBV = hrp:FindFirstChild("ICSW_FlyBV")
            local flyBG = hrp:FindFirstChild("ICSW_FlyBG")

            if getgenv().ICSW_FlyEnabled then
                if not flyBV then
                    flyBV = Instance.new("BodyVelocity")
                    flyBV.Name = "ICSW_FlyBV"
                    flyBV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
                    flyBV.Parent = hrp

                    flyBG = Instance.new("BodyGyro")
                    flyBG.Name = "ICSW_FlyBG"
                    flyBG.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
                    flyBG.P = 9e4
                    flyBG.Parent = hrp
                end

                local cam = workspace.CurrentCamera
                flyBG.CFrame = cam.CFrame
                
                local moveDir = Vector3.new()
                if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + cam.CFrame.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - cam.CFrame.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + cam.CFrame.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - cam.CFrame.RightVector end
                
                if moveDir.Magnitude > 0 then
                    flyBV.Velocity = moveDir.Unit * getgenv().ICSW_FlySpeed
                else
                    flyBV.Velocity = Vector3.zero
                end
            else
                if flyBV then flyBV:Destroy() end
                if flyBG then flyBG:Destroy() end
            end
        end
    end)

    if getgenv().ICSW_JumpRequestConn then getgenv().ICSW_JumpRequestConn:Disconnect() end
    getgenv().ICSW_JumpRequestConn = UserInputService.JumpRequest:Connect(function()
        if getgenv().ICSW_InfJumpEnabled then
            local char = LP.Character
            local hum = char and char:FindFirstChild("Humanoid")
            if hum then
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end
    end)

    if getgenv().ICSW_NoclipLoop then getgenv().ICSW_NoclipLoop:Disconnect() end
    getgenv().ICSW_NoclipLoop = RunService.Stepped:Connect(function()
        if getgenv().ICSW_AutoFarm or getgenv().ICSW_NoclipEnabled then
            local char = LP.Character
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        part.CanCollide = false
                    end
                end
            end
        end
    end)

    -- ================================================================
    -- [Engine] ESP Function
    -- ================================================================
    local function RGBToHex(color)
        return string.format("#%02X%02X%02X", math.clamp(color.R * 255, 0, 255), math.clamp(color.G * 255, 0, 255), math.clamp(color.B * 255, 0, 255))
    end

    local function GetHealthHex(health, maxHealth, defaultColor)
        local pct = math.clamp(health / maxHealth, 0, 1)
        if pct >= 0.99 then return RGBToHex(defaultColor)
        elseif pct >= 0.7 then return "#AFFF00" 
        elseif pct >= 0.4 then return "#FFFF00" 
        elseif pct >= 0.25 then return "#FF8800" 
        else return "#FF0000" end
    end

    local function ClearESP()
        if getgenv().ICSW_ESPInstances then
            for _, esp in pairs(getgenv().ICSW_ESPInstances) do
                if esp.Folder then esp.Folder:Destroy() end
            end
            table.clear(getgenv().ICSW_ESPInstances)
        end
    end

    if getgenv().ICSW_ESPLoop then task.cancel(getgenv().ICSW_ESPLoop) end
    getgenv().ICSW_ESPLoop = task.spawn(function()
        while task.wait(0.1) do
            if not getgenv().ICSW_ESPEnabled then
                if getgenv().ICSW_ESPInstances and next(getgenv().ICSW_ESPInstances) then
                    ClearESP()
                end
                continue
            end

            for _, player in ipairs(Players:GetPlayers()) do
                if player == LP then continue end
                
                local char = player.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                local hum = char and char:FindFirstChild("Humanoid")

                if char and hrp and hum and hum.Health > 0 then
                    if not getgenv().ICSW_ESPInstances[player] then
                        local espGroup = Instance.new("Folder")
                        espGroup.Name = "ESP_" .. player.Name
                        
                        local hl = Instance.new("Highlight")
                        hl.Adornee = char
                        hl.FillColor = getgenv().ICSW_ESPColor
                        hl.OutlineColor = getgenv().ICSW_ESPColor
                        hl.FillTransparency = 0.6
                        hl.OutlineTransparency = 0
                        hl.Parent = espGroup

                        local bg = Instance.new("BillboardGui")
                        bg.Adornee = hrp
                        bg.Size = UDim2.new(0, 200, 0, 50)
                        bg.StudsOffset = Vector3.new(0, 3.5, 0)
                        bg.AlwaysOnTop = true

                        local tl = Instance.new("TextLabel")
                        tl.Size = UDim2.new(1, 0, 1, 0)
                        tl.BackgroundTransparency = 1
                        tl.TextStrokeTransparency = 0.3
                        tl.TextColor3 = getgenv().ICSW_ESPColor
                        tl.TextScaled = false
                        tl.TextSize = 13
                        tl.RichText = true
                        tl.Font = Enum.Font.SourceSansBold
                        tl.Parent = bg
                        
                        bg.Parent = espGroup
                        
                        local target = (gethui and gethui()) or game:GetService("CoreGui")
                        local success = pcall(function() espGroup.Parent = target end)
                        if not success then espGroup.Parent = LP:WaitForChild("PlayerGui") end

                        getgenv().ICSW_ESPInstances[player] = {
                            Folder = espGroup,
                            Highlight = hl,
                            TextLabel = tl,
                            Character = char
                        }
                    else
                        local esp = getgenv().ICSW_ESPInstances[player]
                        if esp.Character ~= char then
                            esp.Folder:Destroy()
                            getgenv().ICSW_ESPInstances[player] = nil
                        else
                            esp.Highlight.FillColor = getgenv().ICSW_ESPColor
                            esp.Highlight.OutlineColor = getgenv().ICSW_ESPColor
                            esp.TextLabel.TextColor3 = getgenv().ICSW_ESPColor
                            
                            local hpHex = GetHealthHex(hum.Health, hum.MaxHealth, getgenv().ICSW_ESPColor)
                            esp.TextLabel.Text = string.format("%s\n<font color=\"%s\">[%.0f / %.0f]</font>", player.Name, hpHex, hum.Health, hum.MaxHealth)
                        end
                    end
                else
                    if getgenv().ICSW_ESPInstances[player] then
                        getgenv().ICSW_ESPInstances[player].Folder:Destroy()
                        getgenv().ICSW_ESPInstances[player] = nil
                    end
                end
            end

            for plr, esp in pairs(getgenv().ICSW_ESPInstances) do
                if not plr.Parent then
                    esp.Folder:Destroy()
                    getgenv().ICSW_ESPInstances[plr] = nil
                end
            end
        end
    end)

    -- ================================================================
    -- [Engine] Spectator Function
    -- ================================================================
    local function GetPlayersList()
        local list = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP then
                table.insert(list, p.Name)
            end
        end
        table.sort(list)
        return list
    end

    if getgenv().ICSW_SpectateLoop then task.cancel(getgenv().ICSW_SpectateLoop) end
    getgenv().ICSW_SpectateLoop = task.spawn(function()
        while task.wait(1) do
            if getgenv().ICSW_SpectatorDropdown then
                getgenv().ICSW_SpectatorDropdown:SetValues(GetPlayersList())
                
                local targetName = getgenv().ICSW_SpectateTarget
                local cam = workspace.CurrentCamera
                
                if targetName and targetName ~= "" then
                    local target = Players:FindFirstChild(targetName)
                    if target and target.Character and target.Character:FindFirstChild("Humanoid") then
                        if cam.CameraSubject ~= target.Character.Humanoid then
                            cam.CameraSubject = target.Character.Humanoid
                        end
                    else
                        if LP.Character and LP.Character:FindFirstChild("Humanoid") then
                            cam.CameraSubject = LP.Character.Humanoid
                        end
                    end
                else
                    if LP.Character and LP.Character:FindFirstChild("Humanoid") and cam.CameraSubject ~= LP.Character.Humanoid then
                        cam.CameraSubject = LP.Character.Humanoid
                    end
                end
            end
        end
    end)

    -- ================================================================
    -- [Engine] Anti-Admin Functions & Event
    -- ================================================================
    local function CheckForAdmin(player)
        if getgenv().ICSW_AntiAdminEnabled and getgenv().ICSW_AdminIDs and getgenv().ICSW_AdminIDs[player.UserId] then
            LP:Kick(string.format("Admin Detect (%d - %s)", player.UserId, player.Name))
        end
    end

    if getgenv().ICSW_AdminCheckConn then getgenv().ICSW_AdminCheckConn:Disconnect() end
    getgenv().ICSW_AdminCheckConn = Players.PlayerAdded:Connect(function(player)
        CheckForAdmin(player)
    end)

    -- ================================================================
    -- [UI] Player Section
    -- ================================================================
    local PlayerSection = tab:AddSection("Player")

    local WalkToggle = PlayerSection:AddToggle("WalkToggle", {
        Title       = "Walk",
        Description = "",
        Default     = false,
        Callback    = function(Value)
            getgenv().ICSW_WalkEnabled = Value
            local char = LP.Character
            local hum = char and char:FindFirstChild("Humanoid")
            if hum then
                if Value then
                    getgenv().ICSW_OriginalWalkSpeed = hum.WalkSpeed
                else
                    hum.WalkSpeed = getgenv().ICSW_OriginalWalkSpeed or 16
                end
            end
        end,
    })
    WalkToggle:Keybind("Key_Walk_New", {Default=Enum.KeyCode.F1, Mode="Toggle"})

    local WalkSlider = PlayerSection:AddSlider("WalkSlider", {
        Title       = "Speed",
        Description = "",
        Default     = 20,
        Min         = 16,
        Max         = 150,
        Rounding    = 0,
        Callback    = function(Value)
            getgenv().ICSW_WalkSpeed = Value
        end,
    })

    local FlyToggle = PlayerSection:AddToggle("FlyToggle", {
        Title       = "Fly",
        Description = "",
        Default     = false,
        Callback    = function(Value)
            getgenv().ICSW_FlyEnabled = Value
        end,
    })
    FlyToggle:Keybind("Key_Fly_New", {Default=Enum.KeyCode.F2, Mode="Toggle"})

    local FlySlider = PlayerSection:AddSlider("FlySlider", {
        Title       = "Speed",
        Description = "",
        Default     = 50,
        Min         = 10,
        Max         = 500,
        Rounding    = 0,
        Callback    = function(Value)
            getgenv().ICSW_FlySpeed = Value
        end,
    })

    local JumpToggle = PlayerSection:AddToggle("JumpToggle", {
        Title       = "Jump",
        Description = "",
        Default     = false,
        Callback    = function(Value)
            getgenv().ICSW_InfJumpEnabled = Value
        end,
    })
    JumpToggle:Keybind("Key_Jump_New", {Default=Enum.KeyCode.F3, Mode="Toggle"})

    local NoclipToggle = PlayerSection:AddToggle("NoclipToggle", {
        Title       = "Noclip",
        Description = "",
        Default     = false,
        Callback    = function(Value)
            getgenv().ICSW_NoclipEnabled = Value
        end,
    })
    NoclipToggle:Keybind("Key_Noclip_New", {Default=Enum.KeyCode.F4, Mode="Toggle"})

    -- ================================================================
    -- [UI] Visuals Section
    -- ================================================================
    local VisualsSection = tab:AddSection("Visuals")

    local ESPToggle = VisualsSection:AddToggle("ESPToggle", {
        Title       = "Player ESP",
        Description = "",
        Default     = false,
        Callback    = function(Value)
            getgenv().ICSW_ESPEnabled = Value
            if not Value then
                ClearESP()
            end
        end,
    })

    local ESPColor = VisualsSection:AddColorpicker("ESPColor", {
        Title          = "ESP Color",
        Description    = "",
        Default        = Color3.fromRGB(255, 182, 211),
        Transparency   = 0,
        Callback       = function(Color)
            getgenv().ICSW_ESPColor = Color
        end,
    })

    -- ================================================================
    -- [UI] Spectator Section
    -- ================================================================
    local SpectatorSection = tab:AddSection("Spectator")

    getgenv().ICSW_SpectatorDropdown = SpectatorSection:AddDropdown("SpectatorDropdown", {
        Title             = "Select Player",
        Description       = "",
        Values            = GetPlayersList(),
        Default           = "", 
        Multi             = false,
        Searchable        = true,
        Callback          = function(Value)
            getgenv().ICSW_SpectateTarget = Value
            local cam = workspace.CurrentCamera
            if Value and Value ~= "" then
                local target = Players:FindFirstChild(Value)
                if target and target.Character and target.Character:FindFirstChild("Humanoid") then
                    cam.CameraSubject = target.Character.Humanoid
                end
            else
                if LP.Character and LP.Character:FindFirstChild("Humanoid") then
                    cam.CameraSubject = LP.Character.Humanoid
                end
            end
        end,
    })

    -- ================================================================
    -- [UI] Security Section
    -- ================================================================
    local SecuritySection = tab:AddSection("Security")

    local hasAdminIDs = false
    if getgenv().ICSW_AdminIDs and type(getgenv().ICSW_AdminIDs) == "table" then
        for _, _ in pairs(getgenv().ICSW_AdminIDs) do
            hasAdminIDs = true
            break
        end
    end

    local AntiAdminToggle = SecuritySection:AddToggle("AntiAdminToggle", {
        Title       = "Anti-Admin",
        Description = "",
        Default     = hasAdminIDs,
        Callback    = function(Value)
            getgenv().ICSW_AntiAdminEnabled = Value
            if Value and getgenv().ICSW_AdminIDs then
                for _, player in ipairs(Players:GetPlayers()) do
                    if getgenv().ICSW_AdminIDs[player.UserId] then
                        LP:Kick(string.format("Admin Detect (%d - %s)", player.UserId, player.Name))
                    end
                end
            end
        end,
    })

    if not hasAdminIDs then
        AntiAdminToggle:Lock("founder didnt set")
    end
	
	-- ================================================================
    -- Cleanup
    -- ================================================================
    if self.Library and self.Library.OnUnload then
        self.Library.OnUnload:Connect(function()
            getgenv().ICSW_ESPEnabled = false
            if getgenv().ICSW_ESPLoop then task.cancel(getgenv().ICSW_ESPLoop) end
            ClearESP()
            
            getgenv().ICSW_WalkEnabled = false
            getgenv().ICSW_FlyEnabled = false
            getgenv().ICSW_InfJumpEnabled = false
            getgenv().ICSW_NoclipEnabled = false
            
            if getgenv().ICSW_PlayerLoop then getgenv().ICSW_PlayerLoop:Disconnect() end
            if getgenv().ICSW_NoclipLoop then getgenv().ICSW_NoclipLoop:Disconnect() end
            if getgenv().ICSW_SpectateLoop then task.cancel(getgenv().ICSW_SpectateLoop) end
            if getgenv().ICSW_JumpRequestConn then getgenv().ICSW_JumpRequestConn:Disconnect() end
            if getgenv().ICSW_AdminCheckConn then getgenv().ICSW_AdminCheckConn:Disconnect() end

            local char = LP.Character
            local hum = char and char:FindFirstChild("Humanoid")
            if hum then hum.WalkSpeed = getgenv().ICSW_OriginalWalkSpeed or 16 end
            
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local flyBV = hrp:FindFirstChild("ICSW_FlyBV")
                local flyBG = hrp:FindFirstChild("ICSW_FlyBG")
                if flyBV then flyBV:Destroy() end
                if flyBG then flyBG:Destroy() end
            end
            
            local cam = workspace.CurrentCamera
            if char and hum and cam.CameraSubject ~= hum then
                cam.CameraSubject = hum
            end
            
            getgenv().ICSW_WalkSpeedHook = false
        end)
    end
end

return SaveManager
