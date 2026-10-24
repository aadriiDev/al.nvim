local Config = require("al.config")
local Util = require("al.utils")
local Files = require("al.files")

-- Bulk code cleanup in the spirit of AZ AL Dev Tools: add the ToolTips that
-- CodeCop AA0218 asks for to page fields and actions, and Captions to table
-- fields, wherever they are missing.
local M = {}

---@param line string
---@return string
local function code(line)
    -- Drop strings and comments so their braces are not counted
    return (line:gsub("'[^']*'", "''"):gsub("//.*$", ""))
end

---@param s string
---@return string
local function unquote(s)
    s = vim.trim(s)
    return s:match('^"(.*)"$') or s
end

--- Finds the body of the block whose header is at `row`.
---@param lines string[]
---@param row integer
---@return integer|nil open, integer|nil close, boolean inline
local function find_body(lines, row)
    local header = code(lines[row])
    local open_col = header:find("{", 1, true)
    if open_col then
        local depth = 0
        for c in header:sub(open_col):gmatch("[{}]") do
            depth = depth + (c == "{" and 1 or -1)
        end
        if depth == 0 then
            return row, row, true
        end
    end
    local r = row
    if not open_col then
        r = row + 1
        while lines[r] and not code(lines[r]):match("%S") do
            r = r + 1
        end
        if not lines[r] or not code(lines[r]):match("^%s*{") then
            return nil, nil, false
        end
    end
    local open, depth = r, 0
    while lines[r] do
        for c in code(lines[r]):gmatch("[{}]") do
            depth = depth + (c == "{" and 1 or -1)
            if depth == 0 then
                return open, r, false
            end
        end
        r = r + 1
    end
    return nil, nil, false
end

--- Whether the direct body of the block (not nested blocks) sets `property`.
---@param lines string[]
---@param open integer
---@param close integer
---@param property string lower case
local function has_property(lines, open, close, property)
    local depth = 0
    for r = open, close do
        local line = code(lines[r])
        if r == open then
            line = line:sub((line:find("{", 1, true) or 0) + 1)
        end
        local l = line:lower()
        if depth == 0 and (l:match("^%s*" .. property .. "%s*=") or l:match("[{;]%s*" .. property .. "%s*=")) then
            return true
        end
        for c in line:gmatch("[{}]") do
            depth = depth + (c == "{" and 1 or -1)
        end
    end
    return false
end

---@class al.Properties.Rule
---@field applies fun(obj: al.Files.Object, lines: string[]): boolean
---@field match fun(line: string): string|nil Returns the name for %1 when the line is a header
---@field property string
---@field template fun(): string

--- Page fields: `field(Name; Rec."No.")`, named after the source field.
---@param line string
local function page_field(line)
    local control, source = line:match("^%s*[Ff][Ii][Ee][Ll][Dd]%s*%(%s*(.-)%s*;%s*(.-)%s*%)")
    if not control or source:find(";", 1, true) then
        return nil
    end
    local field = source:match("^[Rr][Ee][Cc]%.(.+)$")
    return unquote(field or control)
end

--- Page actions: `action(Post)`.
---@param line string
local function page_action(line)
    local name = line:match("^%s*[Aa][Cc][Tt][Ii][Oo][Nn]%s*%(%s*(.-)%s*%)")
    return name and unquote(name) or nil
end

--- Table fields: `field(1; "No."; Code[20])`.
---@param line string
local function table_field(line)
    local name = line:match("^%s*[Ff][Ii][Ee][Ll][Dd]%s*%(%s*%d+%s*;%s*(.-)%s*;")
    return name and unquote(name) or nil
end

---@param lines string[]
local function is_api_page(lines)
    for _, line in ipairs(lines) do
        if line:lower():match("^%s*pagetype%s*=%s*api%s*;") then
            return true
        end
    end
    return false
end

local page_types = { page = true, pageextension = true }
local table_types = { table = true, tableextension = true }

---@type table<string, al.Properties.Rule[]>
local rules = {
    tooltips = {
        {
            applies = function(obj, lines)
                return page_types[obj.type:lower()] and not is_api_page(lines)
            end,
            match = page_field,
            property = "tooltip",
            template = function()
                return Config.objects.field_tooltip
            end,
        },
        {
            applies = function(obj, lines)
                return page_types[obj.type:lower()] and not is_api_page(lines)
            end,
            match = page_action,
            property = "tooltip",
            template = function()
                return Config.objects.action_tooltip
            end,
        },
    },
    captions = {
        {
            applies = function(obj)
                return table_types[obj.type:lower()]
            end,
            match = table_field,
            property = "caption",
            template = function()
                return "%1"
            end,
        },
    },
}

---@param property "tooltip"|"caption"
---@param template string
---@param name string
local function property_line(property, template, name)
    local value = template:gsub("%%1", (name:gsub("%%", "%%%%")))
    local key = property == "tooltip" and "ToolTip" or "Caption"
    return ("%s = '%s';"):format(key, value:gsub("'", "''"))
end

--- Adds the missing properties of `kind` to `lines`.
---@param lines string[]
---@param kind "tooltips"|"captions"
---@return string[] lines, integer added
function M.apply(lines, kind)
    local obj = Files.parse(lines)
    if not obj then
        return lines, 0
    end
    local eol = (lines[1] or ""):match("\r$") and "\r" or ""
    local active = vim.tbl_filter(function(rule)
        return rule.applies(obj, lines)
    end, rules[kind])
    if #active == 0 then
        return lines, 0
    end

    -- Collect edits first, apply them bottom-up so line numbers stay valid
    local edits = {}
    for row, line in ipairs(lines) do
        for _, rule in ipairs(active) do
            local name = rule.match(line)
            if name then
                local open, close, inline = find_body(lines, row)
                if not open or not has_property(lines, open, close, rule.property) then
                    edits[#edits + 1] = { row = row, open = open, inline = inline, name = name, rule = rule }
                end
                break
            end
        end
    end

    local result = vim.list_slice(lines, 1, #lines)
    for idx = #edits, 1, -1 do
        local e = edits[idx]
        local indent = result[e.row]:match("^(%s*)")
        local unit = "    "
        local prop = indent .. unit .. property_line(e.rule.property, e.rule.template(), e.name) .. eol
        if e.inline then
            -- `field(...) { X = 1; }` -> header, {, property, X = 1;, }
            local header = result[e.row]:gsub("\r$", "")
            local before, inside = header:match("^(.-)%s*{(.*)}%s*$")
            local body = { indent .. "{" .. eol, prop }
            if inside and inside:match("%S") then
                body[#body + 1] = indent .. unit .. vim.trim(inside) .. eol
            end
            body[#body + 1] = indent .. "}" .. eol
            result[e.row] = (before or header) .. eol
            for k = #body, 1, -1 do
                table.insert(result, e.row + 1, body[k])
            end
        elseif e.open then
            table.insert(result, e.open + 1, prop)
        else
            -- No body at all: add one
            local header = result[e.row]:gsub("\r$", ""):gsub("%s*$", "")
            result[e.row] = header .. eol
            table.insert(result, e.row + 1, indent .. "}" .. eol)
            table.insert(result, e.row + 1, prop)
            table.insert(result, e.row + 1, indent .. "{" .. eol)
        end
    end
    return result, #edits
end

---@param kind "tooltips"|"captions"
---@param buf integer
---@return integer added
local function apply_buffer(kind, buf)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local result, added = M.apply(lines, kind)
    if added > 0 then
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, result)
    end
    return added
end

local labels = { tooltips = "ToolTips", captions = "Captions" }

--- Command: add missing ToolTips/Captions to the current buffer, or to every
--- AL file of the project with `scope = "project"`.
---@param kind "tooltips"|"captions"
---@param scope? string
function M.command(kind, scope)
    if scope ~= "project" then
        local added = apply_buffer(kind, vim.api.nvim_get_current_buf())
        Util.info(("Added %d %s."):format(added, labels[kind]))
        return
    end
    local root = vim.fs.root(0, "app.json") or vim.fs.root(vim.fn.getcwd(), "app.json")
    if not root then
        Util.error("No app.json found for the current buffer.")
        return
    end
    local total, changed = 0, 0
    for _, path in ipairs(Files.project_files(root)) do
        local buf = Files.find_buf(path)
        local added
        if buf and vim.api.nvim_buf_is_loaded(buf) then
            added = apply_buffer(kind, buf)
        else
            local lines = vim.fn.readfile(path, "b")
            local result
            result, added = M.apply(lines, kind)
            if added > 0 then
                vim.fn.writefile(result, path, "b")
            end
        end
        total = total + added
        changed = changed + (added > 0 and 1 or 0)
    end
    Util.info(("Added %d %s in %d files."):format(total, labels[kind], changed))
end

return M
