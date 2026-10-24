-- Snippets for variable declarations whose name comes from the object:
-- `vrecord` -> `SalesHeader: Record "Sales Header";`. The object is typed
-- first (with LSP completion); the name is filled in when jumping to it, and
-- the al_var cmp source offers the short forms.

local ls = require("luasnip")
local s = ls.snippet
local sn = ls.snippet_node
local i = ls.insert_node
local t = ls.text_node
local c = ls.choice_node
local d = ls.dynamic_node
local fmt = require("luasnip.extras.fmt").fmt

--- Dynamic node body: the best variable name for the object in args[1].
---@param args string[][]
local function name_from_object(args)
    local object = vim.trim((args[1][1] or ""):gsub('"', ""))
    local temporary = args[2] ~= nil and (args[2][1] or ""):match("temporary") ~= nil
    local names = object ~= "" and require("al.variables").suggest(object, temporary) or {}
    return sn(nil, { i(1, names[1] or "v") })
end

local snippets = {
    s(
        { trig = "vrecord", desc = "Variable: Record (name from the table)" },
        fmt("{}: Record {}{};", {
            d(3, name_from_object, { 1, 2 }),
            i(1, "Customer"),
            c(2, { t(""), t(" temporary") }),
        })
    ),
}

for _, kind in ipairs({ "Codeunit", "Report", "XmlPort", "Query", "Page", "TestPage", "Enum", "Interface" }) do
    snippets[#snippets + 1] = s(
        { trig = "v" .. kind:lower(), desc = ("Variable: %s (name from the object)"):format(kind) },
        fmt("{}: " .. kind .. " {};", {
            d(2, name_from_object, { 1 }),
            i(1),
        })
    )
end

return snippets
