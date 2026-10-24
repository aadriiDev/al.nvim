local Lsp = require("al.lsp")
local Workspace = require("al.workspace")
local Util = require("al.utils")
local Config = require("al.config")
local State = require("al.state")

local M = {}

--- Helper: find the AL project root for the current buffer.
---@return string|nil
local function get_project_root()
    local buf = vim.api.nvim_get_current_buf()
    -- Multi-project mode first
    local mp_ok, mp = pcall(require, "al.multiproject")
    if mp_ok then
        local dir = mp.project_for_buf(buf)
        if dir then
            return dir
        end
    end
    -- Workspace registry
    local fname = vim.api.nvim_buf_get_name(buf)
    local ws = Workspace.find({ path = fname })
    if ws then
        return ws.root
    end
    -- Walk up to find app.json (works before LSP has initialized)
    local root = vim.fs.root(buf, "app.json")
    return root
end

--- Helper: read launch.json configs for current buffer's workspace.
---@return al.LaunchConfiguration[]
local function get_launch_configurations()
    local root = get_project_root()
    if not root then
        Util.error("Could not determine AL workspace.")
        return {}
    end
    local ok, configs = pcall(Util.read_json_file, vim.fs.joinpath(root, ".vscode/launch.json"))
    if not ok or not configs then
        Util.error("Could not read launch.json")
        return {}
    end
    return configs.configurations or {}
end

--- Helper: wrap a config-dependent command in coroutine with config resolution.
---@param fn fun(config: al.LaunchConfiguration)
local function with_config(fn)
    -- Always wrap in coroutine — commands like authenticate/publish yield internally
    coroutine.resume(coroutine.create(function()
        local config
        if State.active_config then
            config = State.active_config
        else
            local configs = get_launch_configurations()
            if #configs == 0 then
                return
            end
            config = State.resolve_config(configs)
        end
        if config then
            fn(vim.tbl_extend("force", Config.default_launch_cfg, config))
        end
    end))
end

M.commands = {
    config = function(args)
        require("al.editor_commands.config")(args, get_launch_configurations())
    end,
    lsp = function()
        local clients = Util.get_clients({ bufnr = 0 })
        clients = vim.tbl_filter(function(client)
            return client and Lsp.supports(client)
        end, clients)
        local lines = {}
        for _, client in ipairs(clients) do
            lines[#lines + 1] = "## " .. client.name
            lines[#lines + 1] = "```lua"
            lines[#lines + 1] = "settings = " .. vim.inspect(client.settings)
            lines[#lines + 1] = "```"
        end
        Util.info(lines)
    end,
    build = function()
        coroutine.resume(coroutine.create(function()
            require("al.editor_commands.build")()
        end))
    end,
    publish = function()
        with_config(function(config)
            require("al.editor_commands.publish")(config)
        end)
    end,
    downloadSymbols = function()
        with_config(function(config)
            require("al.editor_commands.download_symbols")(config)
        end)
    end,
    refreshSymbols = function()
        require("al.editor_commands.refresh_symbols")()
    end,
    downloadSource = function()
        require("al.editor_commands.download_source")()
    end,
    authenticate = function()
        with_config(function(config)
            local auth = require("al.editor_commands.auth")
            local result = auth(config)
            if result == "success" then
                Util.info("Authentication successful for " .. config.name)
            elseif result == "fail" then
                Util.error("Authentication failed for " .. config.name)
            elseif result == "cancelled" then
                Util.warn("Authentication cancelled for " .. config.name)
            end
        end)
    end,
    clearCredentialsCache = function()
        with_config(function(config)
            require("al.editor_commands.clear_credential_cache")(config)
        end)
    end,
    definition = function()
        Lsp.go_to_definition()
    end,
    runObject = function(args)
        with_config(function(config)
            require("al.editor_commands.run_object")(config, args)
        end)
    end,
    openInBrowser = function()
        with_config(function(config)
            require("al.editor_commands.open_in_browser")(config)
        end)
    end,
    restartLsp = function()
        require("al.editor_commands.restart_lsp")()
    end,
    installExtension = function()
        require("al.editor_commands.install_extension")()
    end,
    updateExtension = function()
        require("al.editor_commands.install_extension")()
    end,
    eventPublishers = function()
        require("al.editor_commands.event_publishers")()
    end,
    symbolSearch = function(args)
        require("al.editor_commands.symbol_search")(args)
    end,
    dependencies = function()
        require("al.editor_commands.dependencies")()
    end,
    generatePermissionSet = function()
        require("al.editor_commands.generate_permission_set")()
    end,
    renameFile = function()
        require("al.files").current("rename")
    end,
    renameAllFiles = function()
        require("al.files").all("rename")
    end,
    reorganizeFile = function()
        require("al.files").current("reorganize")
    end,
    reorganizeAllFiles = function()
        require("al.files").all("reorganize")
    end,
    gotoLocalVars = function()
        require("al.variables").goto_local()
    end,
    gotoGlobalVars = function()
        require("al.variables").goto_global()
    end,
    sortVariables = function()
        require("al.variables").sort_command()
    end,
    newObject = function(args)
        require("al.objects").new_object(args and args[1])
    end,
    createListPage = function()
        require("al.objects").from_table("page", "List")
    end,
    createCardPage = function()
        require("al.objects").from_table("page", "Card")
    end,
    createReport = function()
        require("al.objects").from_table("report")
    end,
    createQuery = function()
        require("al.objects").from_table("query")
    end,
    createXmlPort = function()
        require("al.objects").from_table("xmlport")
    end,
    addToolTips = function(args)
        require("al.properties").command("tooltips", args and args[1])
    end,
    addFieldCaptions = function(args)
        require("al.properties").command("captions", args and args[1])
    end,
    searchDocs = function(args)
        require("al.editor_commands.search_docs")(args)
    end,
}

function M.execute(input)
    local prefix, args = M.parse(input.args)
    if not prefix or prefix == "" then
        Util.error("Usage: :AL <command>. Available: " .. table.concat(vim.tbl_keys(M.commands), ", "))
        return
    end
    if not M.commands[prefix] then
        Util.error("Unknown command: " .. prefix .. ". Available: " .. table.concat(vim.tbl_keys(M.commands), ", "))
        return
    end
    M.commands[prefix](args)
end

-- Completions for the first argument of a command.
---@type table<string, string[]|fun(): string[]>
local arg_completions = {
    runObject = { "current", "testTool", "eventSubscribers", "databaseLocks", "Page", "Report", "Table", "Query" },
    newObject = function()
        return require("al.objects").types
    end,
    addToolTips = { "project" },
    addFieldCaptions = { "project" },
}

function M.complete(_, line)
    local prefix, args = M.parse(line)
    if #args == 1 and arg_completions[prefix] then
        local values = arg_completions[prefix]
        if type(values) == "function" then
            values = values()
        end
        return vim.tbl_filter(function(value)
            return value:find(args[1], 1, true) == 1
        end, values)
    end
    if #args > 0 then
        return {}
    end

    return vim.tbl_filter(function(key)
        return key:find(prefix, 1, true) == 1
    end, vim.tbl_keys(M.commands))
end

---@return string, string[]
function M.parse(args)
    local parts = vim.split(vim.trim(args), "%s+")
    if parts[1]:find("AL") then
        table.remove(parts, 1)
    end
    if args:sub(-1) == " " then
        parts[#parts + 1] = ""
    end
    return table.remove(parts, 1) or "", parts
end

return M
