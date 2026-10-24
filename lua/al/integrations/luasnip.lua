local M = {}

---@type table<string, boolean>
local loaded_dirs = {}

--- Loads the snippets bundled with the installed AL extension (declared in its
--- package.json under contributes.snippets). Safe to call more than once.
M.load_extension_snippets = function()
    local ok, _ = pcall(require, "luasnip")
    if not ok then
        return
    end

    local ext = require("al.extension").find()
    if not ext or loaded_dirs[ext.dir] then
        return
    end
    loaded_dirs[ext.dir] = true
    require("luasnip.loaders.from_vscode").lazy_load({ paths = { ext.dir } })
end

M.setup = function()
    local ok, _ = pcall(require, "luasnip")
    if not ok then
        return
    end

    local snippet_path = debug.getinfo(1).source:sub(2):gsub("integrations/luasnip.lua", "luasnippets")
    require("luasnip.loaders.from_lua").lazy_load({ paths = snippet_path })
    M.load_extension_snippets()
end

return M
