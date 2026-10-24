local Config = require("al.config")
local Util = require("al.utils")

-- Renames and reorganizes AL files after the object they contain, following
-- the same patterns and settings as the CRS AL Language extension for VS Code.
local M = {}

---@class al.Config.Files
---@field pattern string File name pattern for objects
---@field pattern_extensions string File name pattern for extension objects
---@field pattern_page_customizations string File name pattern for page customizations
---@field subfolder string Folder under the project root used by reorganize ("None" disables it)
---@field on_save "none"|"rename"|"reorganize"
---@field use_git_mv boolean
---@field by_namespace boolean Reorganize into folders built from the namespace
---@field namespace_prefix_to_ignore string
---@field object_name_prefix string Added to the object name when it is missing
---@field object_name_suffix string Added to the object name when it is missing
---@field remove_prefix_from_filename boolean
---@field remove_suffix_from_filename boolean
---@field remove_underscore_from_filename boolean
---@field read_crs_settings boolean Read CRS.* keys from the project's .vscode/settings.json

-- CRS.* setting -> key in al.Config.Files
local crs_keys = {
    ["CRS.FileNamePattern"] = "pattern",
    ["CRS.FileNamePatternExtensions"] = "pattern_extensions",
    ["CRS.FileNamePatternPageCustomizations"] = "pattern_page_customizations",
    ["CRS.AlSubFolderName"] = "subfolder",
    ["CRS.OnSaveAlFileAction"] = "on_save",
    ["CRS.RenameWithGit"] = "use_git_mv",
    ["CRS.ReorganizeByNamespace"] = "by_namespace",
    ["CRS.NamespacePrefixToIgnore"] = "namespace_prefix_to_ignore",
    ["CRS.ObjectNamePrefix"] = "object_name_prefix",
    ["CRS.ObjectNameSuffix"] = "object_name_suffix",
    ["CRS.RemovePrefixFromFilename"] = "remove_prefix_from_filename",
    ["CRS.RemoveSuffixFromFilename"] = "remove_suffix_from_filename",
    ["CRS.RemoveUnderscoreFromFilename"] = "remove_underscore_from_filename",
}

local on_save_values = { donothing = "none", none = "none", rename = "rename", reorganize = "reorganize" }

-- Object type -> { short, pascal, id = has an id, base = keyword before the base object }
local object_types = {
    table = { short = "Tab", pascal = "Table", id = true },
    tableextension = { short = "Tab", pascal = "TableExt", id = true, base = "extends" },
    page = { short = "Pag", pascal = "Page", id = true },
    pageextension = { short = "Pag", pascal = "PageExt", id = true, base = "extends" },
    pagecustomization = { short = "Pag", pascal = "PageCust", base = "customizes" },
    report = { short = "Rep", pascal = "Report", id = true },
    reportextension = { short = "Rep", pascal = "ReportExt", id = true, base = "extends" },
    codeunit = { short = "Cod", pascal = "Codeunit", id = true },
    query = { short = "Que", pascal = "Query", id = true },
    xmlport = { short = "Xml", pascal = "XmlPort", id = true },
    enum = { short = "Enum", pascal = "Enum", id = true },
    enumextension = { short = "Enum", pascal = "EnumExt", id = true, base = "extends" },
    permissionset = { short = "PermissionSet", pascal = "PermissionSet", id = true },
    permissionsetextension = {
        short = "PermissionSetExt",
        pascal = "PermissionSetExt",
        id = true,
        base = "extends",
    },
    interface = { short = "Iface", pascal = "Interface" },
    profile = { short = "Prof", pascal = "Profile" },
    controladdin = { short = "ControlAddIn", pascal = "ControlAddin" },
    entitlement = { short = "Entitlement", pascal = "Entitlement" },
}

---@class al.Files.Object
---@field type string Object type as written in the file (e.g. "pageextension")
---@field id string
---@field name string
---@field base_name string Extended/customized object name
---@field base_id string Base object id, from a `// 21` comment after the base name
---@field namespace string
---@field test boolean Codeunit with Subtype = Test
---@field line integer 1-based line of the object declaration

--- Case-insensitive Lua pattern for a keyword ("extends" -> "[eE][xX]...").
---@param word string
local function nocase(word)
    return (word:gsub("%a", function(c)
        return "[" .. c:lower() .. c:upper() .. "]"
    end))
end

--- Reads an object name (quoted or a bare identifier) at the start of `s`.
---@param s string
---@return string|nil name, string rest, boolean quoted
local function read_name(s)
    s = s:gsub("^%s+", "")
    local quoted = s:match('^"([^"]*)"')
    if quoted then
        return quoted, s:sub(#quoted + 3), true
    end
    local word = s:match("^([%w_]+)")
    if word then
        return word, s:sub(#word + 1), false
    end
    return nil, s, false
end

--- Parses the object declared in `lines`.
---@param lines string[]
---@return al.Files.Object|nil
function M.parse(lines)
    local obj
    local namespace = ""
    local test = false
    for i, line in ipairs(lines) do
        if not line:match("^%s*//") then
            namespace = namespace ~= "" and namespace or (line:match("^%s*[Nn]amespace%s+([%w_.]+)%s*;") or "")
            if not obj then
                local kind, rest = line:match("^%s*(%a+)(.*)$")
                local def = kind and object_types[kind:lower()]
                if def then
                    local id = ""
                    if def.id then
                        id, rest = rest:match("^%s+(%d+)(.*)$")
                    end
                    local name
                    if id then
                        name, rest = read_name(rest)
                    end
                    if name then
                        obj = { type = kind, id = id, name = vim.trim(name), base_name = "", base_id = "", line = i }
                        if def.base then
                            local after = rest:match("^%s+" .. nocase(def.base) .. "%s+(.*)$")
                            if after then
                                local base
                                base, rest = read_name(after)
                                obj.base_name = vim.trim(base or "")
                                obj.base_id = rest:match("^%s*//%s*(%d+)") or ""
                            end
                        end
                    end
                end
            elseif obj.type:lower() == "codeunit" and line:lower():match("^%s*subtype%s*=%s*test%s*;") then
                test = true
            end
        end
    end
    if obj then
        obj.namespace = namespace
        obj.test = test
    end
    return obj
end

--- Decodes a VS Code settings file (JSON with comments and trailing commas).
---@param text string
---@return table|nil
local function decode_jsonc(text)
    text = text:gsub(",(%s*[}%]])", "%1")
    local ok, result = pcall(vim.json.decode, text, { skip_comments = true })
    if ok and type(result) == "table" then
        return result
    end
    return nil
end

--- Effective settings for the project at `root`: plugin config, overridden by
--- the CRS.* keys in the project's .vscode/settings.json.
---@param root string|nil
---@return al.Config.Files
function M.settings(root)
    local settings = vim.deepcopy(Config.files)
    if root and settings.read_crs_settings then
        local path = vim.fs.joinpath(root, ".vscode", "settings.json")
        local fd = io.open(path)
        if fd then
            local json = decode_jsonc(fd:read("*a")) or {}
            fd:close()
            for crs_key, key in pairs(crs_keys) do
                local value = json[crs_key]
                if value ~= nil and value ~= vim.NIL then
                    settings[key] = value
                end
            end
        end
    end
    settings.on_save = on_save_values[tostring(settings.on_save):lower()] or "none"
    return settings
end

---@param name string
---@param settings al.Config.Files
---@return string
local function add_affixes(name, settings)
    local prefix, suffix = settings.object_name_prefix or "", settings.object_name_suffix or ""
    if prefix ~= "" and name:sub(1, #prefix) ~= prefix then
        name = prefix .. name
    end
    if suffix ~= "" and name:sub(-#suffix) ~= suffix then
        name = name .. suffix
    end
    return name
end

---@param name string
---@param settings al.Config.Files
---@return string
local function remove_affixes(name, settings)
    local prefix, suffix = settings.object_name_prefix or "", settings.object_name_suffix or ""
    if settings.remove_prefix_from_filename and prefix ~= "" and name:sub(1, #prefix) == prefix then
        name = name:sub(#prefix + 1)
    end
    if settings.remove_suffix_from_filename and suffix ~= "" and name:sub(-#suffix) == suffix then
        name = name:sub(1, -#suffix - 1)
    end
    return name
end

---@param s string
local function for_filename(s)
    return (s:gsub('[<>:"/\\|%?%*]', "_"))
end

---@param s string
local function alphanumeric(s)
    return (s:gsub("[^%w_]", ""))
end

--- Object name with the configured prefix/suffix applied.
---@param obj al.Files.Object
---@param settings al.Config.Files
---@return string
function M.fixed_name(obj, settings)
    return add_affixes(obj.name, settings)
end

--- File name for `obj` according to the configured patterns.
---@param obj al.Files.Object
---@param settings al.Config.Files
---@return string
function M.file_name(obj, settings)
    local def = object_types[obj.type:lower()]
    local pattern = settings.pattern
    if def.base == "extends" then
        pattern = settings.pattern_extensions
    elseif def.base == "customizes" then
        pattern = settings.pattern_page_customizations
    end

    local fixed = M.fixed_name(obj, settings)
    -- Over 30 characters is not a valid AL name: keep the original for the short form
    local short = alphanumeric(remove_affixes(#fixed > 30 and obj.name or fixed, settings))
    local values = {
        ["<Prefix>"] = settings.object_name_prefix or "",
        ["<Suffix>"] = settings.object_name_suffix or "",
        ["<ObjectType>"] = obj.type,
        ["<ObjectTypeShort>"] = def.short,
        ["<ObjectTypeShortPascalCase>"] = def.pascal,
        ["<ObjectTypeShortUpper>"] = def.short:upper(),
        ["<ObjectId>"] = obj.id,
        ["<ObjectName>"] = for_filename(remove_affixes(fixed, settings)),
        ["<ObjectNameShort>"] = short,
        ["<BaseName>"] = for_filename(obj.base_name),
        ["<BaseNameShort>"] = alphanumeric(obj.base_name),
        ["<BaseId>"] = obj.base_id,
    }
    local result = pattern:gsub("<%a+>", function(key)
        return values[key]
    end)
    if settings.remove_underscore_from_filename then
        result = result:gsub("_", "")
    end
    return result
end

--- Folder where reorganize puts `obj`.
---@param obj al.Files.Object
---@param settings al.Config.Files
---@param root string
---@return string
function M.target_dir(obj, settings, root)
    if obj.test then
        return vim.fs.joinpath(root, "test")
    end
    local dir = vim.fs.joinpath(root, settings.subfolder)
    if settings.by_namespace and obj.namespace ~= "" then
        local namespace = obj.namespace
        local ignore = settings.namespace_prefix_to_ignore or ""
        if ignore ~= "" and namespace:sub(1, #ignore) == ignore then
            namespace = namespace:sub(#ignore + 1):gsub("^%.", "")
        end
        for _, part in ipairs(vim.split(namespace, ".", { plain = true, trimempty = true })) do
            dir = vim.fs.joinpath(dir, part)
        end
    else
        dir = vim.fs.joinpath(dir, obj.type)
    end
    if obj.type:lower() == "controladdin" then
        dir = vim.fs.joinpath(dir, alphanumeric(M.fixed_name(obj, settings)))
    end
    return dir
end

--- Moves a file, creating the destination folder. Uses `git mv` when asked,
--- falling back to a plain rename for untracked files.
---@param from string
---@param to string
---@param use_git boolean
---@return boolean ok, string|nil err
function M.move(from, to, use_git)
    -- A case-only change on a case-insensitive file system "exists" already
    local case_only = from:lower() == to:lower()
    if not case_only and vim.uv.fs_stat(to) then
        return false, "File already exists: " .. to
    end
    vim.fn.mkdir(vim.fs.dirname(to), "p")
    if use_git then
        local res = vim.system({ "git", "mv", "--", from, to }, { cwd = vim.fs.dirname(from), text = true }):wait()
        if res.code == 0 then
            return true
        end
    end
    local ok, err = vim.uv.fs_rename(from, to)
    if not ok then
        return false, err
    end
    return true
end

--- Buffer whose file is `path` (bufnr() would treat the path as a pattern).
---@param path string
---@return integer|nil
local function find_buf(path)
    -- Buffer names may have symlinks resolved (/var -> /private/var on macOS)
    local real = vim.uv.fs_realpath(path) or path
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local name = vim.fs.normalize(vim.api.nvim_buf_get_name(buf))
        if name ~= "" and (name == path or (vim.uv.fs_realpath(name) or name) == real) then
            return buf
        end
    end
    return nil
end

--- Points `buf` at `to`. A loaded buffer is written, so LSP clients get
--- didClose/didOpen for the new path.
---@param buf integer
---@param to string
local function retarget_buffer(buf, to)
    local old_name = vim.api.nvim_buf_get_name(buf)
    vim.api.nvim_buf_set_name(buf, to)
    -- nvim_buf_set_name leaves an unlisted buffer behind for the old name
    for _, stale in ipairs(vim.api.nvim_list_bufs()) do
        if stale ~= buf and vim.api.nvim_buf_get_name(stale) == old_name then
            pcall(vim.api.nvim_buf_delete, stale, { force = true })
        end
    end
    if vim.api.nvim_buf_is_loaded(buf) then
        vim.api.nvim_buf_call(buf, function()
            vim.cmd("silent! write!")
        end)
    end
end

--- Applies the object name prefix/suffix to the declaration line.
---@param lines string[]
---@param obj al.Files.Object
---@param settings al.Config.Files
---@return string|nil line New declaration line, nil when unchanged
local function fix_declaration(lines, obj, settings)
    local fixed = M.fixed_name(obj, settings)
    if fixed == obj.name then
        return nil
    end
    if #fixed > 30 then
        Util.warn(("Object name %q would exceed 30 characters, not renamed."):format(fixed))
        return nil
    end
    local line = lines[obj.line]
    local quoted = '"' .. obj.name .. '"'
    local s, e = line:find(quoted, 1, true)
    if not s then
        s, e = line:find("%f[%w_]" .. vim.pesc(obj.name) .. "%f[^%w_]")
    end
    if not s then
        return nil
    end
    return line:sub(1, s - 1) .. '"' .. fixed .. '"' .. line:sub(e + 1)
end

---@alias al.Files.Mode "rename"|"reorganize"

local process_file

--- Renames or reorganizes one file.
---@param path string Absolute path
---@param mode al.Files.Mode
---@param opts? { root?: string, settings?: al.Config.Files }
---@return string|nil new_path, string|nil err
function M.process(path, mode, opts)
    opts = opts or {}
    path = vim.fs.normalize(path)
    local root = opts.root or vim.fs.root(path, "app.json")
    if not root then
        return nil, "No app.json found for " .. path
    end
    local settings = opts.settings or M.settings(root)
    if mode == "reorganize" and (settings.subfolder == nil or settings.subfolder == "None") then
        return nil, "Reorganize is disabled: files.subfolder (CRS.AlSubFolderName) is 'None'."
    end

    local buf = find_buf(path)
    local loaded = buf ~= nil and vim.api.nvim_buf_is_loaded(buf)
    if not loaded then
        return process_file(path, mode, root, settings, buf, false)
    end
    -- Writes below fire BufWritePost again: keep the on-save hook out of it
    vim.b[buf].al_files_renaming = true
    local ok, new_path, err = pcall(process_file, path, mode, root, settings, buf, true)
    vim.b[buf].al_files_renaming = nil
    if not ok then
        return nil, new_path
    end
    return new_path, err
end

---@param path string
---@param mode al.Files.Mode
---@param root string
---@param settings al.Config.Files
---@param buf integer|nil Buffer showing `path`
---@param loaded boolean Whether `buf` holds the file contents
---@return string|nil new_path, string|nil err
process_file = function(path, mode, root, settings, buf, loaded)
    -- "b": keep CRLF line endings when the file is rewritten
    local lines = loaded and vim.api.nvim_buf_get_lines(buf, 0, -1, false) or vim.fn.readfile(path, "b")
    local obj = M.parse(lines)
    if not obj then
        return nil, "No AL object found in " .. vim.fs.basename(path)
    end

    local declaration = fix_declaration(lines, obj, settings)
    if declaration then
        if loaded then
            vim.api.nvim_buf_set_lines(buf, obj.line - 1, obj.line, false, { declaration })
        else
            lines[obj.line] = declaration
            vim.fn.writefile(lines, path, "b")
        end
    end
    if loaded and vim.bo[buf].modified then
        vim.api.nvim_buf_call(buf, function()
            vim.cmd("silent! write")
        end)
    end

    local dir = mode == "reorganize" and M.target_dir(obj, settings, root) or vim.fs.dirname(path)
    local target = vim.fs.joinpath(dir, M.file_name(obj, settings))
    if target == path then
        return path
    end
    local ok, err = M.move(path, target, settings.use_git_mv)
    if not ok then
        return nil, err
    end
    if buf then
        retarget_buffer(buf, target)
    end
    return target
end

--- AL files of the project at `root`, skipping hidden folders (.alpackages, .snapshots...).
---@param root string
---@return string[]
function M.project_files(root)
    local files = {}
    for name, kind in
        vim.fs.dir(root, {
            depth = math.huge,
            skip = function(dir)
                return not vim.fs.basename(dir):match("^%.")
            end,
        })
    do
        if kind == "file" and name:match("%.al$") then
            files[#files + 1] = vim.fs.joinpath(root, name)
        end
    end
    table.sort(files)
    return files
end

--- Command: rename/reorganize the current file.
---@param mode al.Files.Mode
function M.current(mode)
    local path = vim.api.nvim_buf_get_name(0)
    if path == "" or not path:match("%.al$") then
        Util.error("The current buffer is not an AL file.")
        return
    end
    local new_path, err = M.process(path, mode)
    if not new_path then
        Util.error(err)
    elseif new_path ~= vim.fs.normalize(path) then
        Util.info("Moved to " .. vim.fn.fnamemodify(new_path, ":~:."))
    end
end

--- Command: rename/reorganize every AL file of the current project.
---@param mode al.Files.Mode
function M.all(mode)
    local root = vim.fs.root(0, "app.json") or vim.fs.root(vim.fn.getcwd(), "app.json")
    if not root then
        Util.error("No app.json found for the current buffer.")
        return
    end
    local files = M.project_files(root)
    local verb = mode == "reorganize" and "Reorganize" or "Rename"
    local answer = vim.fn.confirm(("%s %d AL files in %s?"):format(verb, #files, root), "&Yes\n&No", 2)
    if answer ~= 1 then
        return
    end
    local settings = M.settings(root)
    local moved, errors = 0, {}
    for _, path in ipairs(files) do
        local new_path, err = M.process(path, mode, { root = root, settings = settings })
        if not new_path then
            errors[#errors + 1] = err
        elseif new_path ~= path then
            moved = moved + 1
        end
    end
    Util.info(("%s: %d of %d files moved."):format(verb, moved, #files))
    if #errors > 0 then
        Util.warn(table.concat(errors, "\n"))
    end
end

M.setup = function()
    vim.api.nvim_create_autocmd("BufWritePost", {
        group = vim.api.nvim_create_augroup("al-files", { clear = true }),
        pattern = "*.al",
        -- The rename writes the buffer again; nested so the LSP hears about it
        nested = true,
        callback = function(ev)
            if vim.b[ev.buf].al_files_renaming then
                return
            end
            local path = vim.api.nvim_buf_get_name(ev.buf)
            local root = vim.fs.root(path, "app.json")
            if not root then
                return
            end
            local settings = M.settings(root)
            if settings.on_save == "none" then
                return
            end
            local _, err = M.process(path, settings.on_save, { root = root, settings = settings })
            if err then
                Util.warn(err)
            end
        end,
    })
end

return M
