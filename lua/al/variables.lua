local Config = require("al.config")
local Util = require("al.utils")

-- Helpers for AL variable declarations, in the spirit of the AL Variable
-- Helper extension for VS Code: names from the type, jumping to the var
-- sections and sorting declarations as CodeCop AA0021 expects.
local M = {}

---@class al.Config.Variables
---@field ignore_prefixes string[] Removed from object names before building variable names
---@field ignore_suffixes string[] Removed from object names before building variable names

-- Types whose variable name is usually derived from the object name
local object_kinds = {
    record = "Record",
    codeunit = "Codeunit",
    report = "Report",
    xmlport = "XmlPort",
    query = "Query",
    page = "Page",
    testpage = "TestPage",
    enum = "Enum",
    interface = "Interface",
}

-- Declaration order required by AA0021; other types keep their order after these
local aa0021_order = {
    "record",
    "report",
    "codeunit",
    "xmlport",
    "page",
    "query",
    "notification",
    "bigtext",
    "dateformula",
    "recordid",
    "recordref",
    "fieldref",
    "filterpagebuilder",
}
local aa0021_rank = {}
for idx, kind in ipairs(aa0021_order) do
    aa0021_rank[kind] = idx
end

---@class al.Variables.Declaration
---@field name string Variable name as written (may be empty)
---@field name_start integer 0-based byte column where the name starts
---@field name_end integer 0-based byte column after the name
---@field kind string Canonical type ("Record", "Page"...)
---@field object string Object name without quotes or namespace
---@field temporary boolean

--- Parses a single-line declaration such as `Cust: Record Customer temporary;`.
---@param line string
---@return al.Variables.Declaration|nil
function M.parse_declaration(line)
    local indent, name, rest = line:match('^(%s*)([%w_]*)(%s*:.*)$')
    if not indent then
        indent, name, rest = line:match('^(%s*)("[^"]*")(%s*:.*)$')
    end
    if not indent then
        return nil
    end
    local kind, object = rest:match("^%s*:%s*(%a+)%s+(.-)%s*;?%s*$")
    kind = kind and object_kinds[kind:lower()]
    if not kind or object == "" then
        return nil
    end
    local temporary = false
    local without = object:match("^(.-)%s+[Tt][Ee][Mm][Pp][Oo][Rr][Aa][Rr][Yy]$")
    if without then
        object, temporary = without, true
    end
    local quoted = object:match('^"(.*)"$')
    if quoted then
        object = quoted
    else
        -- Namespace-qualified: Microsoft.Sales.Customer.Customer
        object = object:match("([^%.]+)$")
    end
    return {
        name = name,
        name_start = #indent,
        name_end = #indent + #name,
        kind = kind,
        object = object,
        temporary = temporary,
    }
end

---@param name string
---@return string
local function strip_affixes(name)
    local opts = Config.variables or {}
    local prefixes = vim.list_extend({}, opts.ignore_prefixes or {})
    local files_prefix = (Config.files or {}).object_name_prefix
    if files_prefix and files_prefix ~= "" then
        prefixes[#prefixes + 1] = files_prefix
    end
    for _, prefix in ipairs(prefixes) do
        if prefix ~= "" and name:sub(1, #prefix) == prefix then
            name = name:sub(#prefix + 1)
        end
    end
    local suffixes = vim.list_extend({}, opts.ignore_suffixes or {})
    local files_suffix = (Config.files or {}).object_name_suffix
    if files_suffix and files_suffix ~= "" then
        suffixes[#suffixes + 1] = files_suffix
    end
    for _, suffix in ipairs(suffixes) do
        if suffix ~= "" and #name > #suffix and name:sub(-#suffix) == suffix then
            name = name:sub(1, -#suffix - 1)
        end
    end
    return vim.trim(name)
end

--- Variable names for an object, best first: full name, abbreviated name and
--- capitals only. Temporary records get the "Temp" prefix required by AA0073.
---@param object string Object name, e.g. "Sales Header"
---@param temporary? boolean
---@return string[]
function M.suggest(object, temporary)
    local abbreviations = require("al.abbreviations")
    local name = strip_affixes(object)

    local full = name:gsub("[^%w_]", "")
    local raw = {}
    for word in name:gmatch("%u?%l*") do
        if word ~= "" then
            raw[#raw + 1] = word
        end
    end
    local words, k = {}, 1
    while k <= #raw do
        local matched
        for _, phrase in ipairs(abbreviations.phrases) do
            local fits = k + #phrase - 1 <= #raw
            for j = 1, #phrase do
                fits = fits and raw[k + j - 1]:upper() == phrase[j]
            end
            if fits then
                words[#words + 1] = phrase.abbr
                k = k + #phrase
                matched = true
                break
            end
        end
        if not matched then
            words[#words + 1] = abbreviations.words[raw[k]:upper()] or raw[k]
            k = k + 1
        end
    end
    local short = table.concat(words)
    local tag = name:gsub("[^%u]", "")

    local names, seen = {}, {}
    for _, candidate in ipairs({ full, short, tag }) do
        candidate = candidate:gsub("^[%d%.]+", "")
        if temporary then
            candidate = "Temp" .. candidate
        end
        if candidate ~= "" and candidate ~= "Temp" and not seen[candidate] then
            seen[candidate] = true
            names[#names + 1] = candidate
        end
    end
    return names
end

--- Whether `line` declares a procedure or trigger.
---@param line string
local function is_routine(line)
    local l = line:lower()
    return l:match("^%s*procedure[%s%(]")
        or l:match("^%s*local%s+procedure[%s%(]")
        or l:match("^%s*internal%s+procedure[%s%(]")
        or l:match("^%s*protected%s+procedure[%s%(]")
        or l:match("^%s*trigger[%s%(]")
end

---@param line string
local function is_var(line)
    local l = line:lower()
    return l:match("^%s*var%s*$") or l:match("^%s*protected%s+var%s*$")
end

--- Whether the var section at `row` (1-based) belongs to a procedure/trigger.
--- Walks back to the routine header, or to a line closing a block (global).
---@param lines string[]
---@param row integer
local function is_local_var(lines, row)
    for r = row - 1, 1, -1 do
        local line = lines[r]
        if is_routine(line) then
            return true
        end
        local l = line:lower()
        if l:match("^%s*end;") or l:match("^%s*}") or l:match("^%s*{") then
            return false
        end
    end
    return false
end

---@param row integer 1-based
---@param col integer 0-based
local function jump(row, col)
    vim.cmd("normal! m'")
    vim.api.nvim_win_set_cursor(0, { row, col })
end

--- Jumps to the var section of the procedure or trigger at the cursor. When
--- it has none, one is added before `begin`.
function M.goto_local()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local cursor = vim.api.nvim_win_get_cursor(0)[1]
    local header
    for r = cursor, 1, -1 do
        if is_routine(lines[r]) then
            header = r
            break
        end
    end
    -- The routine ends at the first `end;` indented like its header
    if header then
        local indent = lines[header]:match("^(%s*)")
        for r = header + 1, cursor - 1 do
            if lines[r]:match("^" .. indent .. "[Ee][Nn][Dd];") then
                header = nil
                break
            end
        end
    end
    if not header then
        Util.warn("The cursor is not inside a procedure or trigger.")
        return
    end
    for r = header + 1, #lines do
        local l = lines[r]:lower()
        if is_var(l) then
            local last = r
            while lines[last + 1] and not lines[last + 1]:lower():match("^%s*begin%s*$") do
                last = last + 1
            end
            jump(last, #lines[last])
            return
        end
        if l:match("^%s*begin%s*$") then
            local indent = lines[r]:match("^(%s*)")
            local unit = vim.bo.expandtab and string.rep(" ", vim.fn.shiftwidth()) or "\t"
            vim.api.nvim_buf_set_lines(0, r - 1, r - 1, false, { indent .. "var", indent .. unit })
            jump(r + 1, #indent + #unit)
            return
        end
    end
    Util.warn("No begin found for this procedure.")
end

--- Jumps to the object's global var section.
function M.goto_global()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for r, line in ipairs(lines) do
        if is_var(line) and not is_local_var(lines, r) then
            local last = r
            while lines[last + 1] and lines[last + 1]:match("%S") and not is_routine(lines[last + 1]) do
                local l = lines[last + 1]:lower()
                if l:match("^%s*}") or l:match("^%s*%[") or is_var(l) then
                    break
                end
                last = last + 1
            end
            jump(last, #lines[last])
            return
        end
    end
    Util.warn("This object has no global var section.")
end

---@param line string
local function ends_section(line)
    local l = line:lower()
    return l:match("^%s*begin%s*$")
        or is_routine(l)
        or is_var(l)
        or l:match("^%s*%[")
        or l:match("^%s*}")
        or l:match("^%s*{")
end

--- Sorts the declarations of one var section (lines `first`..`last`, 1-based).
---@param lines string[]
---@param first integer
---@param last integer
---@return string[]|nil sorted Nil when the section cannot be sorted safely
local function sort_section(lines, first, last)
    local entries, pending = {}, {}
    for r = first, last do
        local line = lines[r]
        if line:match("^%s*#") then
            return nil -- preprocessor directives: leave the section alone
        end
        pending[#pending + 1] = line
        local code = line:gsub("//.*$", "")
        if code:match(";%s*$") then
            local declaration = vim.iter(pending):find(function(l)
                return l:match(":")
            end) or ""
            local kind = (declaration:match(":%s*(%a+)") or ""):lower()
            entries[#entries + 1] = { lines = pending, rank = aa0021_rank[kind] or #aa0021_order + 1 }
            pending = {}
        end
    end
    if #pending > 0 and vim.iter(pending):any(function(l)
        return l:match("%S")
    end) then
        return nil -- unterminated declaration
    end
    for idx, entry in ipairs(entries) do
        entry.idx = idx
    end
    table.sort(entries, function(a, b)
        if a.rank ~= b.rank then
            return a.rank < b.rank
        end
        return a.idx < b.idx
    end)
    local sorted = {}
    for _, entry in ipairs(entries) do
        vim.list_extend(sorted, entry.lines)
    end
    vim.list_extend(sorted, pending)
    return sorted
end

--- Sorts every var section of the buffer in the order required by AA0021.
---@param buf? integer
---@return integer changed Number of sections reordered
function M.sort(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local changed = 0
    local r = 1
    while r <= #lines do
        if is_var(lines[r]) then
            local first, last = r + 1, r
            while lines[last + 1] and not ends_section(lines[last + 1]) do
                last = last + 1
            end
            -- Trailing blank lines stay where they are
            while last >= first and not lines[last]:match("%S") do
                last = last - 1
            end
            local sorted = last >= first and sort_section(lines, first, last)
            if sorted and not vim.deep_equal(sorted, vim.list_slice(lines, first, last)) then
                vim.api.nvim_buf_set_lines(buf, first - 1, last, false, sorted)
                for k, line in ipairs(sorted) do
                    lines[first + k - 1] = line
                end
                changed = changed + 1
            end
            r = math.max(last, r) + 1
        else
            r = r + 1
        end
    end
    return changed
end

--- Command: sort the current buffer's var sections.
function M.sort_command()
    local changed = M.sort()
    if changed == 0 then
        Util.info("Variables are already in AA0021 order.")
    else
        Util.info(("Sorted %d var section%s."):format(changed, changed == 1 and "" or "s"))
    end
end

return M
