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

return SaveManager
