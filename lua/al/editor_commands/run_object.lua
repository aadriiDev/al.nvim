local Config = require("al.config")
local Util = require("al.utils")
local Lsp = require("al.lsp")

-- Well-known system pages, usable as `:AL runObject <name>` (keep in sync
-- with the completion in al.cmd).
---@type table<string, { type: string, id: integer }>
local presets = {
    testTool = { type = "Page", id = 130451 },
    eventSubscribers = { type = "Page", id = 9510 },
    databaseLocks = { type = "Page", id = 9511 },
}

-- Object types that can be started from the web client.
---@type table<string, string>
local runnable = {
    table = "Table",
    page = "Page",
    report = "Report",
    query = "Query",
    xmlport = "XmlPort",
    codeunit = "Codeunit",
}

--- Reads the object type and id declared in `buf` (e.g. `page 50100 "My Page"`).
---@param buf integer
---@return string|nil type, integer|nil id, string|nil declared
local function detect_object(buf)
    for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
        local kind, id = line:match("^%s*(%a+)%s+(%d+)%s")
        if kind then
            return runnable[kind:lower()], tonumber(id), kind
        end
    end
    return nil, nil, nil
end

---@param config al.LaunchConfiguration
---@param args string[]
local run_object = function(config, args)
    local buf = vim.api.nvim_get_current_buf()
    local client = Lsp.get_client_for_buf(buf)
    if not client then
        Util.error("No AL language server attached to the current buffer.")
        return
    end

    args = args or {}
    local preset = presets[args[1] or ""]
    if args[1] == "current" then
        local object_type, object_id, declared = detect_object(buf)
        if not object_type then
            Util.error(declared and ("Cannot run a " .. declared .. " object.") or "No AL object found in buffer.")
            return
        end
        args = { object_type, tostring(object_id) }
    elseif preset then
        args = { preset.type, tostring(preset.id) }
    end

    -- Override startup object from args: :AL runObject Page 22
    if #args >= 2 then
        config = vim.deepcopy(config)
        config.startupObjectType = args[1]
        config.startupObjectId = tonumber(args[2]) or config.startupObjectId
    end

    local params = {
        configuration = config,
        browserInfo = {
            browser = Config.lsp.browser,
            incognito = false,
        },
    }

    client:request("al/runObject", params, function(err, result)
        if err then
            Util.error("Run object failed: " .. (err.message or vim.inspect(err)))
            return
        end
        if result and result.success then
            Util.info("Object launched: " .. (config.startupObjectType or "") .. " " .. (config.startupObjectId or ""))
        else
            Util.error("Failed to run object")
        end
    end)
end

return run_object
