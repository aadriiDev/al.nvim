local Util = require("al.utils")

-- Builds the Business Central web client URL for a launch configuration and
-- opens it, same as "launchBrowser" does in the VS Code AL extension.
-- https://learn.microsoft.com/dynamics365/business-central/dev-itpro/developer/devenv-web-client-urls

---@param config al.LaunchConfiguration
---@return boolean
local function is_cloud(config)
    return config.environmentType == "Sandbox"
        or config.environmentType == "Production"
        or (config.environmentName ~= nil and config.environmentName ~= "")
end

---@param config al.LaunchConfiguration
---@return string|nil key, string|nil id
local function startup_object(config)
    local id = config.startupObjectId
    if not id then
        return nil, nil
    end
    local key = ({ page = "page", table = "table", report = "report", query = "query" })[(
        config.startupObjectType or "Page"
    ):lower()] or "page"
    return key, tostring(id)
end

---@param config al.LaunchConfiguration
---@return string
local function build_url(config)
    local query = {}
    if config.startupCompany and config.startupCompany ~= "" then
        query[#query + 1] = "company=" .. vim.uri_encode(config.startupCompany)
    end
    local key, id = startup_object(config)
    if key then
        query[#query + 1] = key .. "=" .. id
    end

    local base
    if is_cloud(config) then
        base = "https://businesscentral.dynamics.com"
        -- <aadtenantid>: the Microsoft Entra tenant domain/GUID, not the
        -- on-premises "tenant" query parameter.
        if config.tenant and config.tenant ~= "" then
            base = base .. "/" .. config.tenant
        end
        if config.environmentName and config.environmentName ~= "" then
            base = base .. "/" .. config.environmentName
        end
    else
        base = config.server or ""
        if config.port and config.port ~= "" and config.port ~= 0 then
            base = base .. ":" .. tostring(config.port)
        end
        if config.serverInstance and config.serverInstance ~= "" then
            base = base .. "/" .. config.serverInstance
        end
        if config.tenant and config.tenant ~= "" then
            query[#query + 1] = "tenant=" .. vim.uri_encode(config.tenant)
        end
    end

    local url = base .. "/"
    if #query > 0 then
        url = url .. "?" .. table.concat(query, "&")
    end
    return url
end

local M = {}
M.build_url = build_url

---@param config al.LaunchConfiguration
function M.open(config)
    local url = build_url(config)
    Util.info("Opening: " .. url)
    if vim.fn.has("win32") == 1 then
        vim.fn.jobstart({ "rundll32", "url.dll,FileProtocolHandler", url }, { detach = true })
    else
        local _, err = vim.ui.open(url)
        if err then
            Util.error("Failed to open browser: " .. err)
        end
    end
end

return setmetatable(M, {
    __call = function(_, config)
        M.open(config)
    end,
})
