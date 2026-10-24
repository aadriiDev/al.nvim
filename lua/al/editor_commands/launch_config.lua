local Util = require("al.utils")

-- Wizard for `:AL newLaunchConfig`: builds a launch configuration (server,
-- authentication, tenant...) and appends it to the project's
-- .vscode/launch.json, the same file the "AL: Generate launch.json" command
-- of the VS Code AL extension writes to.

---@param prompt string
---@param default? string
---@return string|nil
local function ask_input(prompt, default)
    local co = coroutine.running()
    vim.ui.input({ prompt = prompt, default = default }, function(value)
        coroutine.resume(co, value and value ~= "" and value or nil)
    end)
    return coroutine.yield()
end

---@param prompt string
---@param items string[]
---@return string|nil
local function ask_select(prompt, items)
    local co = coroutine.running()
    vim.ui.select(items, { prompt = prompt }, function(choice)
        coroutine.resume(co, choice)
    end)
    return coroutine.yield()
end

---@param root string
---@return string
local function launch_json_path(root)
    return vim.fs.joinpath(root, ".vscode", "launch.json")
end

---@param root string
---@return table configurations, table rest (every other top-level key, e.g. "version")
local function read_launch_json(root)
    local fd = io.open(launch_json_path(root))
    if not fd then
        return {}, { version = "0.2.0" }
    end
    local json = Util.decode_jsonc(fd:read("*a")) or {}
    fd:close()
    local configurations = json.configurations
    json.configurations = nil
    if type(configurations) ~= "table" then
        configurations = {}
    end
    if not json.version then
        json.version = "0.2.0"
    end
    return configurations, json
end

--- Minimal pretty-printer, just enough for launch.json: strings/numbers/
--- booleans, an ordered list of fields per configuration, and an array of
--- configurations. `fields` gives each configuration's key order.
---@param value any Scalar only (no nested array/object values are used here)
---@return string
local function encode_value(value)
    return vim.json.encode(value)
end

---@param config table
---@param fields string[]
---@param indent integer
---@param trailing_comma boolean
---@param lines string[] Appended to in place
local function append_config(config, fields, indent, trailing_comma, lines)
    local pad, pad_in = string.rep(" ", indent), string.rep(" ", indent + 4)
    lines[#lines + 1] = pad .. "{"
    local present = {}
    for _, key in ipairs(fields) do
        if config[key] ~= nil then
            present[#present + 1] = key
        end
    end
    for i, key in ipairs(present) do
        local comma = i < #present and "," or ""
        lines[#lines + 1] = pad_in .. vim.json.encode(key) .. ": " .. encode_value(config[key]) .. comma
    end
    lines[#lines + 1] = pad .. "}" .. (trailing_comma and "," or "")
end

--- Minimal pretty-printer, just enough for launch.json: strings/numbers/
--- booleans, and an ordered list of fields per configuration (`fields`).
---@param configurations table[]
---@param fields string[]
---@param rest table Every other top-level key (e.g. "version")
---@return string[] lines
local function encode(configurations, fields, rest)
    local lines = { "{" }
    for key, value in pairs(rest) do
        lines[#lines + 1] = ("    %s: %s,"):format(vim.json.encode(key), encode_value(value))
    end
    if #configurations == 0 then
        lines[#lines + 1] = '    "configurations": []'
    else
        lines[#lines + 1] = '    "configurations": ['
        for i, config in ipairs(configurations) do
            append_config(config, fields, 8, i < #configurations, lines)
        end
        lines[#lines + 1] = "    ]"
    end
    lines[#lines + 1] = "}"
    return lines
end

-- Key order used when writing a configuration, matching the AL extension's
-- own "AL: Generate launch.json" output.
local field_order = {
    "name",
    "request",
    "type",
    "server",
    "port",
    "serverInstance",
    "environmentName",
    "tenant",
    "authentication",
    "usePublicURLFromServer",
    "startupObjectId",
    "startupObjectType",
    "breakOnError",
}

---@return table|nil config
local function build_config()
    local name = ask_input("Nombre de la configuracion: ")
    if not name then
        return nil
    end

    local kind = ask_select("Tipo de entorno:", {
        "On-premises / servidor local",
        "Sandbox en la nube (Business Central Online)",
    })
    if not kind then
        return nil
    end

    local config = {
        name = name,
        type = "al",
        request = "launch",
        breakOnError = "All",
    }

    if kind:match("^On%-premises") then
        config.server = ask_input("URL del servidor: ", "http://bcserver")
        if not config.server then
            return nil
        end
        local port = ask_input("Puerto: ", "7049")
        config.port = port and tonumber(port) or 7049
        config.serverInstance = ask_input("Nombre de instancia (serverInstance): ", "BC")
        config.tenant = ask_input("Tenant: ", "default")
        config.authentication = ask_select("Autenticacion:", { "UserPassword", "Windows", "AAD", "MicrosoftEntraID" })
            or "UserPassword"
    else
        config.server = "https://businesscentral.dynamics.com"
        config.environmentName = ask_input("Nombre del entorno (environmentName): ", "Sandbox")
        config.tenant = ask_input("Tenant (dominio o id): ", "default")
        config.authentication = "MicrosoftEntraID"
        config.usePublicURLFromServer = true
    end

    local startup_id = ask_input("Objeto de inicio (startupObjectId), vacio para omitir: ", "22")
    if startup_id then
        config.startupObjectId = tonumber(startup_id)
        config.startupObjectType = ask_select("Tipo de objeto de inicio:", { "Page", "Table", "Report", "Codeunit" })
            or "Page"
    end

    return config
end

---@param root string Project root (folder with app.json)
return function(root)
    local co = coroutine.running()
    assert(co, "launch_config must run inside a coroutine")

    local config = build_config()
    if not config then
        Util.warn("Creacion de la configuracion cancelada.")
        return
    end

    local configurations, rest = read_launch_json(root)
    configurations[#configurations + 1] = config

    local path = launch_json_path(root)
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile(encode(configurations, field_order, rest), path)

    Util.info(("Configuracion %q anadida a %s"):format(config.name, vim.fn.fnamemodify(path, ":~:.")))

    local buf = require("al.files").find_buf(path)
    if buf then
        vim.api.nvim_buf_call(buf, function()
            vim.cmd("checktime")
        end)
    end
end
