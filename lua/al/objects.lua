local Config = require("al.config")
local Util = require("al.utils")
local Files = require("al.files")

-- New object wizards, in the spirit of AZ AL Dev Tools / AL Code Outline:
-- pick the next free id from app.json, name the file after the object and
-- generate list/card pages, reports, queries and xmlports from a table.
local M = {}

---@class al.Config.Objects
---@field application_area string ApplicationArea of generated pages and reports
---@field application_area_on_fields boolean Repeat ApplicationArea on every field instead of the object
---@field field_tooltip string ToolTip of generated page fields; %1 is the field caption
---@field action_tooltip string ToolTip added to page actions by :AL addToolTips; %1 is the action name
---@field list_usage_category string UsageCategory of generated list pages

-- Object types `:AL newObject` can create
M.types = {
    "table",
    "tableextension",
    "page",
    "pageextension",
    "codeunit",
    "report",
    "reportextension",
    "query",
    "xmlport",
    "enum",
    "enumextension",
    "interface",
    "permissionset",
}

local without_id = { interface = true }
local extensions = { tableextension = true, pageextension = true, reportextension = true, enumextension = true }

--- Field types that cannot be shown on pages or exported as columns
local skipped_field_types = { blob = true, media = true, mediaset = true }

---@param name string
---@return string
local function quote(name)
    if name:match("^[%a_][%w_]*$") then
        return name
    end
    return '"' .. name .. '"'
end

---@param name string
---@return string
local function identifier(name)
    return (name:gsub("[^%w_]", ""))
end

---@param s string
---@return string
local function label(s)
    return "'" .. s:gsub("'", "''") .. "'"
end

--- Decodes app.json (which may contain comments).
---@param root string
---@return table
local function read_app_json(root)
    local fd = io.open(vim.fs.joinpath(root, "app.json"))
    if not fd then
        return {}
    end
    local text = fd:read("*a")
    fd:close()
    local ok, json = pcall(vim.json.decode, text, { skip_comments = true })
    return ok and type(json) == "table" and json or {}
end

--- Ids already used by objects of `object_type` in the project.
---@param root string
---@param object_type string
---@return table<integer, boolean>
function M.used_ids(root, object_type)
    local used = {}
    for _, path in ipairs(Files.project_files(root)) do
        local obj = Files.parse(vim.fn.readfile(path, "", 50))
        if obj and obj.type:lower() == object_type and obj.id ~= "" then
            used[tonumber(obj.id)] = true
        end
    end
    return used
end

--- First id in the app.json ranges not used by another object of this type.
---@param root string
---@param object_type string
---@return integer|nil
function M.next_id(root, object_type)
    local app = read_app_json(root)
    local ranges = app.idRanges
    if (not ranges or #ranges == 0) and app.idRange then
        ranges = { app.idRange }
    end
    if not ranges or #ranges == 0 then
        return nil
    end
    local used = M.used_ids(root, object_type)
    for _, range in ipairs(ranges) do
        for id = range.from, range.to do
            if not used[id] then
                return id
            end
        end
    end
    return nil
end

---@class al.Objects.Field
---@field id string
---@field name string
---@field type string

--- Fields of the table declared in `lines` that can go on pages and reports
--- (no FlowFilters, removed fields or Blob/Media types).
---@param lines string[]
---@return al.Objects.Field[]
function M.table_fields(lines)
    local fields = {}
    local current
    for _, line in ipairs(lines) do
        local id, name, field_type = line:match("^%s*[Ff][Ii][Ee][Ll][Dd]%s*%(%s*(%d+)%s*;%s*(.-)%s*;%s*(.-)%s*%)")
        if id then
            name = name:match('^"(.*)"$') or name
            current = { id = id, name = name, type = field_type }
            local base_type = (field_type:match("^(%a+)") or ""):lower()
            if not skipped_field_types[base_type] then
                fields[#fields + 1] = current
            end
        elseif current then
            local l = line:lower()
            if l:match("fieldclass%s*=%s*flowfilter") or l:match("obsoletestate%s*=%s*removed") then
                if fields[#fields] == current then
                    fields[#fields] = nil
                end
                current = nil
            elseif l:match("^%s*keys%s*$") then
                break
            end
        end
    end
    return fields
end

---@param lines string[]
---@param indent integer
---@param body string[]
local function append(lines, indent, body)
    local pad = string.rep(" ", indent)
    for _, line in ipairs(body) do
        lines[#lines + 1] = line == "" and "" or pad .. line
    end
end

---@param opts al.Config.Objects
---@return string[]
local function object_app_area(opts)
    if opts.application_area_on_fields then
        return {}
    end
    return { "ApplicationArea = " .. opts.application_area .. ";" }
end

---@param field al.Objects.Field
---@param opts al.Config.Objects
---@return string[]
local function page_field(field, opts)
    local lines = { ("field(%s; Rec.%s)"):format(quote(field.name), quote(field.name)), "{" }
    if opts.application_area_on_fields then
        lines[#lines + 1] = "    ApplicationArea = " .. opts.application_area .. ";"
    end
    local tooltip = opts.field_tooltip:gsub("%%1", (field.name:gsub("%%", "%%%%")))
    lines[#lines + 1] = "    ToolTip = " .. label(tooltip) .. ";"
    lines[#lines + 1] = "}"
    return lines
end

---@class al.Objects.Spec
---@field type string Object type, lower case ("page", "tableextension"...)
---@field id? integer
---@field name string
---@field base? string Extended object (extensions) or source table (pages from a table)
---@field page_type? "List"|"Card" For pages
---@field fields? al.Objects.Field[] Fields of the source table
---@field namespace? string

--- Source lines for a new object.
---@param spec al.Objects.Spec
---@return string[]
function M.render(spec)
    local opts = Config.objects
    local name = quote(spec.name)
    local header
    if without_id[spec.type] then
        header = ("%s %s"):format(spec.type, name)
    else
        header = ("%s %d %s"):format(spec.type, spec.id, name)
    end
    if extensions[spec.type] then
        header = header .. " extends " .. quote(spec.base)
    end
    local lines = { header, "{" }
    if spec.namespace and spec.namespace ~= "" then
        table.insert(lines, 1, "namespace " .. spec.namespace .. ";")
        table.insert(lines, 2, "")
    end
    local fields = spec.fields or {}

    if spec.type == "table" then
        append(lines, 4, {
            "Caption = " .. label(spec.name) .. ";",
            "DataClassification = CustomerContent;",
            "",
            "fields",
            "{",
            '    field(1; "No."; Code[20])',
            "    {",
            "        Caption = 'No.';",
            "    }",
            "}",
            "",
            "keys",
            "{",
            '    key(PK; "No.")',
            "    {",
            "        Clustered = true;",
            "    }",
            "}",
        })
    elseif spec.type == "page" then
        -- Repeaters need a source table
        local list = spec.page_type ~= "Card" and spec.base ~= nil
        append(lines, 4, {
            "Caption = " .. label(spec.name) .. ";",
            "PageType = " .. (list and "List" or "Card") .. ";",
        })
        if spec.base then
            lines[#lines + 1] = "    SourceTable = " .. quote(spec.base) .. ";"
        end
        append(lines, 4, object_app_area(opts))
        if list then
            lines[#lines + 1] = "    UsageCategory = " .. opts.list_usage_category .. ";"
        end
        append(lines, 4, { "", "layout", "{", "    area(Content)", "    {" })
        append(lines, 12, { (list and "repeater(General)" or "group(General)"), "{" })
        if list then
            -- Placeholder for skeletons, to be replaced with fields
            if #fields == 0 then
                append(lines, 16, { "// field(...; Rec....) { }" })
            end
        else
            append(lines, 16, { "Caption = 'General';" })
        end
        for _, field in ipairs(fields) do
            append(lines, 16, page_field(field, opts))
        end
        append(lines, 12, { "}" })
        append(lines, 4, { "    }", "}" })
    elseif spec.type == "report" then
        append(lines, 4, { "Caption = " .. label(spec.name) .. ";" })
        append(lines, 4, object_app_area(opts))
        append(lines, 4, { "UsageCategory = ReportsAndAnalysis;", "", "dataset", "{" })
        if spec.base then
            append(lines, 8, { ("dataitem(%s; %s)"):format(identifier(spec.base), quote(spec.base)), "{" })
            for _, field in ipairs(fields) do
                append(lines, 12, { ("column(%s; %s) { }"):format(identifier(field.name), quote(field.name)) })
            end
            append(lines, 8, { "}" })
        end
        append(lines, 4, { "}" })
    elseif spec.type == "query" then
        append(lines, 4, { "Caption = " .. label(spec.name) .. ";", "QueryType = Normal;", "", "elements", "{" })
        if spec.base then
            append(lines, 8, { ("dataitem(%s; %s)"):format(identifier(spec.base), quote(spec.base)), "{" })
            -- A query needs at least one column; every table has SystemId
            for _, field in ipairs(#fields > 0 and fields or { { name = "SystemId" } }) do
                append(lines, 12, { ("column(%s; %s) { }"):format(identifier(field.name), quote(field.name)) })
            end
            append(lines, 8, { "}" })
        end
        append(lines, 4, { "}" })
    elseif spec.type == "xmlport" then
        append(lines, 4, {
            "Caption = " .. label(spec.name) .. ";",
            "Format = Xml;",
            "",
            "schema",
            "{",
            "    textelement(Root)",
            "    {",
        })
        if spec.base then
            local alias = identifier(spec.base)
            append(lines, 12, { ("tableelement(%s; %s)"):format(alias, quote(spec.base)), "{" })
            for _, field in ipairs(fields) do
                local element = ("fieldelement(%s; %s.%s) { }"):format(identifier(field.name), alias, quote(field.name))
                append(lines, 16, { element })
            end
            append(lines, 12, { "}" })
        end
        append(lines, 4, { "    }", "}" })
    elseif spec.type == "codeunit" then
        append(lines, 4, { "procedure MyProcedure()", "begin", "end;" })
    elseif spec.type == "enum" then
        append(lines, 4, {
            "Extensible = true;",
            "Caption = " .. label(spec.name) .. ";",
            "",
            'value(0; " ")',
            "{",
            "    Caption = ' ', Locked = true;",
            "}",
        })
    elseif spec.type == "interface" then
        append(lines, 4, { "procedure MyProcedure();" })
    elseif spec.type == "permissionset" then
        append(lines, 4, { "Assignable = true;", "Caption = " .. label(spec.name) .. ";" })
    elseif spec.type == "tableextension" then
        append(lines, 4, { "fields", "{", "}" })
    elseif spec.type == "pageextension" then
        append(lines, 4, { "layout", "{", "}", "", "actions", "{", "}" })
    elseif spec.type == "reportextension" then
        append(lines, 4, { "dataset", "{", "}" })
    elseif spec.type == "enumextension" then
        append(lines, 4, { "value(50100; MyValue)", "{", "    Caption = 'My Value';", "}" })
    end
    lines[#lines + 1] = "}"
    return lines
end

--- Folder for a new file: where reorganize would put it when files are
--- reorganized on save; in a folder per object type when the current file is
--- in one (src/table/ -> src/page/); else next to the current file, else
--- <root>/<subfolder>.
---@param obj al.Files.Object
---@param root string
---@return string
local function new_file_dir(obj, root)
    local settings = Files.settings(root)
    if settings.on_save == "reorganize" and settings.subfolder ~= "None" then
        return Files.target_dir(obj, settings, root)
    end
    local current = vim.api.nvim_buf_get_name(0)
    if current:match("%.al$") and vim.fs.root(current, "app.json") == root then
        local dir = vim.fs.dirname(current)
        local current_obj = Files.parse(vim.api.nvim_buf_get_lines(0, 0, 50, false))
        if current_obj and vim.fs.basename(dir):lower() == current_obj.type:lower() then
            return vim.fs.joinpath(vim.fs.dirname(dir), obj.type)
        end
        return dir
    end
    if settings.subfolder and settings.subfolder ~= "None" then
        return vim.fs.joinpath(root, settings.subfolder)
    end
    return root
end

--- Writes a new object to disk and opens it.
---@param spec al.Objects.Spec
---@param root string
---@return string|nil path, string|nil err
function M.create(spec, root)
    local lines = M.render(spec)
    local obj = Files.parse(lines)
    if not obj then
        return nil, "Could not build the object."
    end
    local settings = Files.settings(root)
    local path = vim.fs.joinpath(new_file_dir(obj, root), Files.file_name(obj, settings))
    if vim.uv.fs_stat(path) then
        return nil, "File already exists: " .. path
    end
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile(lines, path)
    vim.cmd.edit(vim.fn.fnameescape(path))
    return path
end

---@param prompt string
---@param default string
---@param cb fun(value: string)
local function ask_name(prompt, default, cb)
    vim.ui.input({ prompt = prompt, default = default }, function(value)
        value = value and vim.trim(value)
        if not value or value == "" then
            return
        end
        if #value > 30 then
            Util.error(("Object names are limited to 30 characters (%q has %d)."):format(value, #value))
            return
        end
        cb(value)
    end)
end

--- Like ask_name, but an empty answer is passed on as nil.
---@param prompt string
---@param cb fun(value: string|nil)
local function ask_optional(prompt, cb)
    vim.ui.input({ prompt = prompt }, function(value)
        if value == nil then
            return -- cancelled
        end
        value = vim.trim(value)
        cb(value ~= "" and value or nil)
    end)
end

-- Types built on a source table, asked for by :AL newObject
local table_based = { page = true, report = true, query = true, xmlport = true }

---@return string|nil
local function project_root()
    local root = vim.fs.root(0, "app.json") or vim.fs.root(vim.fn.getcwd(), "app.json")
    if not root then
        Util.error("No app.json found for the current buffer or working directory.")
    end
    return root
end

---@param spec al.Objects.Spec
---@param root string
local function finish(spec, root)
    if not without_id[spec.type] then
        spec.id = spec.id or M.next_id(root, spec.type)
        if not spec.id then
            Util.error("No free " .. spec.type .. " id in the app.json idRanges.")
            return
        end
    end
    spec.name = Files.fixed_name({ name = spec.name }, Files.settings(root))
    if spec.namespace == nil then
        -- Same namespace as the file we are in (AA0247)
        local current = Files.parse(vim.api.nvim_buf_get_lines(0, 0, 50, false))
        spec.namespace = current and current.namespace or nil
    end
    local path, err = M.create(spec, root)
    if not path then
        Util.error(err)
    else
        Util.info(("Created %s %s in %s"):format(spec.type, spec.id or "", vim.fn.fnamemodify(path, ":~:.")))
    end
end

--- Command: create a new object. `object_type` is asked for when missing.
---@param object_type? string
function M.new_object(object_type)
    local root = project_root()
    if not root then
        return
    end
    local function with_type(kind)
        kind = kind:lower()
        if not vim.tbl_contains(M.types, kind) then
            Util.error("Unknown object type: " .. kind)
            return
        end
        ask_name(kind .. " name: ", "", function(name)
            if extensions[kind] then
                ask_name("Extends: ", "", function(base)
                    finish({ type = kind, name = name, base = base }, root)
                end)
            elseif table_based[kind] then
                ask_optional("Source table (optional): ", function(base)
                    if not base and kind == "query" then
                        Util.error("A query needs a source table.")
                        return
                    end
                    finish({ type = kind, name = name, base = base, page_type = "List" }, root)
                end)
            else
                finish({ type = kind, name = name }, root)
            end
        end)
    end
    if object_type and object_type ~= "" then
        with_type(object_type)
        return
    end
    vim.ui.select(M.types, { prompt = "New AL object" }, function(choice)
        if choice then
            with_type(choice)
        end
    end)
end

-- Default object names for generated objects
local suffixes = { List = " List", Card = " Card", report = "", query = " Query", xmlport = " Export" }

--- Command: create a page, report, query or xmlport from the table in the
--- current buffer (all its fields), or from a table name asked for (no fields).
---@param object_type "page"|"report"|"query"|"xmlport"
---@param page_type? "List"|"Card"
function M.from_table(object_type, page_type)
    local root = project_root()
    if not root then
        return
    end
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local obj = Files.parse(lines)
    local function generate(table_name, fields)
        local default = table_name .. (suffixes[page_type or object_type] or "")
        ask_name(object_type .. " name: ", #default <= 30 and default or "", function(name)
            finish({ type = object_type, name = name, base = table_name, page_type = page_type, fields = fields }, root)
        end)
    end
    if obj and obj.type:lower() == "table" then
        generate(obj.name, M.table_fields(lines))
    else
        ask_name("Source table: ", "", function(table_name)
            generate(table_name, {})
        end)
    end
end

return M
