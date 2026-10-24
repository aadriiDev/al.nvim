local Variables = require("al.variables")

-- nvim-cmp source "al_var": variable names for the declaration under the
-- cursor, built from its type (`|: Record "Sales Header";` -> SalesHeader,
-- SalesHdr, SH).
local source = {}

source.new = function()
    return setmetatable({}, { __index = source })
end

function source:is_available()
    return vim.bo.filetype == "al"
end

function source:get_debug_name()
    return "al_var"
end

function source:complete(params, callback)
    local ctx = params.context
    local declaration = Variables.parse_declaration(ctx.cursor_line)
    local col = ctx.cursor.col - 1
    if not declaration or col < declaration.name_start or col > declaration.name_end then
        callback({ items = {}, isIncomplete = false })
        return
    end
    local row = ctx.cursor.row - 1
    local range = {
        start = { line = row, character = declaration.name_start },
        ["end"] = { line = row, character = declaration.name_end },
    }
    local temporary = declaration.temporary and " temporary" or ""
    local detail = ('%s "%s"%s'):format(declaration.kind, declaration.object, temporary)
    local items = {}
    for idx, name in ipairs(Variables.suggest(declaration.object, declaration.temporary)) do
        items[#items + 1] = {
            label = name,
            filterText = name,
            sortText = ("%02d"):format(idx),
            kind = vim.lsp.protocol.CompletionItemKind.Variable,
            detail = detail,
            textEdit = { newText = name, range = range },
        }
    end
    callback({ items = items, isIncomplete = false })
end

return source
