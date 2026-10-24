---@type al.Config.mod
local Config = require("al.config")
---@type al.Utils.mod
local Utils = require("al.utils")

-- Locates and installs the "AL Language extension for Microsoft Dynamics 365
-- Business Central" (ms-dynamics-smb.al) without needing VS Code.
local M = {}

M.extension_id = "ms-dynamics-smb.al"
M.gallery_url = "https://marketplace.visualstudio.com/_apis/public/gallery"

-- Number of installed versions kept in extensionsPath after an install
-- (the new one plus the previous one, as a rollback).
local KEEP_VERSIONS = 2

local is_windows = vim.fn.has("win32") == 1

---@class al.Extension
---@field dir string Absolute path to the extension folder
---@field version string Version string, e.g. "18.1.2842859"

---@param path string
local function exists(path)
    return vim.uv.fs_stat(path) ~= nil
end

---@param path string
local function normalize(path)
    path = vim.fs.normalize(vim.fn.expand(path))
    return (path:gsub("[/\\]$", ""))
end

---@param version string
---@return integer[]
local function parse_version(version)
    local parts = {}
    for n in version:gmatch("%d+") do
        parts[#parts + 1] = tonumber(n)
    end
    return parts
end

--- Returns true when version `a` is greater than version `b`.
---@param a string
---@param b string
function M.version_gt(a, b)
    local pa, pb = parse_version(a), parse_version(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then
            return x > y
        end
    end
    return false
end

--- Folders scanned for the extension, in priority order.
---@return string[]
function M.search_paths()
    local paths = {}
    for _, p in ipairs({ Config.extensionsPath, Config.vscodeExtensionsPath }) do
        if p and p ~= "" then
            p = normalize(p)
            if not vim.tbl_contains(paths, p) then
                paths[#paths + 1] = p
            end
        end
    end
    return paths
end

--- Lists every AL extension found directly under `base`.
---@param base string
---@return al.Extension[]
function M.list(base)
    local found = {}
    local handle = vim.uv.fs_scandir(normalize(base))
    if not handle then
        return found
    end
    while true do
        local name, t = vim.uv.fs_scandir_next(handle)
        if not name then
            break
        end
        local version = name:match("^ms%-dynamics%-smb%.al%-(%d[%d%.]*)")
        if version and (t == "directory" or t == "link") then
            found[#found + 1] = { dir = vim.fs.joinpath(normalize(base), name), version = version }
        end
    end
    table.sort(found, function(a, b)
        return M.version_gt(a.version, b.version)
    end)
    return found
end

--- Finds the extension to use. The first search path containing an extension
--- wins, and within it the highest version.
---@param base? string Only search this folder
---@return al.Extension|nil
function M.find(base)
    for _, path in ipairs(base and { base } or M.search_paths()) do
        local ext = M.list(path)[1]
        if ext then
            return ext
        end
    end
    return nil
end

---@return string
local function platform_folder()
    local os_name = vim.uv.os_uname().sysname:lower()
    if os_name:match("windows") then
        return "win32"
    elseif os_name:match("darwin") then
        return "darwin"
    end
    return "linux"
end

---@class al.Extension.Server
---@field native? string Self-contained executable (extension <= v17, or Windows)
---@field dll? string Framework-dependent assembly, started with `dotnet`

--- Resolves the EditorServices host of an extension. Since v18 the extension
--- ships a single cross-platform .dll in bin/ instead of per-platform binaries
--- in bin/<platform>/.
---@param ext al.Extension
---@return al.Extension.Server
function M.server(ext)
    local name = "Microsoft.Dynamics.Nav.EditorServices.Host"
    local bin = vim.fs.joinpath(ext.dir, "bin")
    local platform_bin = vim.fs.joinpath(bin, platform_folder())
    local server = {}

    local native_candidates = { vim.fs.joinpath(platform_bin, name) }
    if is_windows then
        native_candidates = { vim.fs.joinpath(platform_bin, name .. ".exe"), vim.fs.joinpath(bin, name .. ".exe") }
    end
    for _, p in ipairs(native_candidates) do
        if exists(p) then
            server.native = p
            break
        end
    end

    for _, p in ipairs({ vim.fs.joinpath(bin, name .. ".dll"), vim.fs.joinpath(platform_bin, name .. ".dll") }) do
        if exists(p) then
            server.dll = p
            break
        end
    end

    return server
end

--- Command prefix that starts the language server, or nil if not installed.
---@return string[]|nil
function M.server_cmd()
    local ext = M.find()
    if not ext then
        return nil
    end
    Config.language_extension_version = ext.version
    local server = M.server(ext)
    if server.native then
        return { server.native }
    elseif server.dll then
        return { Config.dotnetPath, server.dll }
    end
    return nil
end

---@param cmd string[]
---@param cb fun(ok: boolean, err?: string, stdout?: string)
local function run(cmd, cb)
    local ok, err = pcall(vim.system, cmd, { text = true }, function(res)
        if res.code == 0 then
            cb(true, nil, res.stdout)
        else
            cb(false, vim.trim(res.stderr or "") ~= "" and vim.trim(res.stderr) or ("exit code " .. res.code))
        end
    end)
    if not ok then
        cb(false, tostring(err))
    end
end

--- Keeps `current` active: removes newer versions (e.g. a pre-release installed
--- earlier) and all but the KEEP_VERSIONS most recent remaining ones.
---@param target string
---@param current string
local function prune(target, current)
    local kept = 0
    for _, ext in ipairs(M.list(target)) do
        if M.version_gt(ext.version, current) or kept >= KEEP_VERSIONS then
            vim.fn.delete(ext.dir, "rf")
        else
            kept = kept + 1
        end
    end
end

--- Asks the Marketplace for the most recent version, skipping pre-releases
--- unless `extensionPrerelease` is enabled. The `latest/vspackage` endpoint
--- can't be used for this: it also returns pre-releases.
---@param cb fun(version?: string, err?: string)
function M.latest_version(cb)
    local body = vim.json.encode({
        filters = { { criteria = { { filterType = 7, value = M.extension_id } }, pageSize = 1 } },
        flags = 17, -- IncludeVersions + IncludeVersionProperties
    })
    run({
        "curl",
        "-fsSL",
        "--compressed",
        "-X",
        "POST",
        "-H",
        "Content-Type: application/json",
        "-H",
        "Accept: application/json;api-version=3.0-preview.1",
        "-d",
        body,
        M.gallery_url .. "/extensionquery",
    }, function(ok, err, stdout)
        if not ok then
            return cb(nil, err)
        end
        local decoded, data = pcall(vim.json.decode, stdout or "")
        local ext = decoded and vim.tbl_get(data, "results", 1, "extensions", 1)
        if not ext then
            return cb(nil, "unexpected Marketplace response")
        end
        for _, v in ipairs(ext.versions or {}) do
            local prerelease = false
            for _, prop in ipairs(v.properties or {}) do
                if prop.key == "Microsoft.VisualStudio.Code.PreRelease" and prop.value == "true" then
                    prerelease = true
                end
            end
            if v.version and (Config.extensionPrerelease or not prerelease) then
                return cb(v.version)
            end
        end
        cb(nil, "no suitable version found")
    end)
end

--- Downloads the latest extension from the Visual Studio Marketplace and
--- installs it into `extensionsPath`.
---@param opts? { on_done?: fun(ext?: al.Extension, updated?: boolean) }
function M.install(opts)
    opts = opts or {}
    local done = function(ext, updated)
        if opts.on_done then
            vim.schedule(function()
                opts.on_done(ext, updated)
            end)
        end
    end

    if vim.fn.executable("curl") == 0 or vim.fn.executable("unzip") == 0 then
        Utils.error("`curl` and `unzip` are required to install the AL Language extension.")
        return done(nil)
    end

    local target = normalize(Config.extensionsPath)
    local staging = vim.fs.joinpath(target, ".staging-" .. Utils.create_uuid())
    local vsix = vim.fs.joinpath(staging, "al.vsix")

    local fail = function(msg)
        vim.schedule(function()
            vim.fn.delete(staging, "rf")
            Utils.error("AL Language extension install failed: " .. msg)
            done(nil)
        end)
    end

    Utils.info("Checking the latest AL Language extension version...")
    M.latest_version(function(version, verr)
        if not version then
            return fail("version lookup: " .. tostring(verr))
        end
        vim.schedule(function()
            local ext = { dir = vim.fs.joinpath(target, M.extension_id .. "-" .. version), version = version }
            if exists(ext.dir) then
                -- Already downloaded: just make sure it is the active version
                local active = M.find()
                prune(target, version)
                Utils.info("AL Language extension " .. version .. " is already installed.")
                return done(ext, not active or active.version ~= version)
            end

            vim.fn.mkdir(staging, "p")
            Utils.info("Downloading AL Language extension " .. version .. "...")
            local url = ("%s/publishers/ms-dynamics-smb/vsextensions/al/%s/vspackage"):format(M.gallery_url, version)
            run({ "curl", "-fsSL", "--compressed", "-o", vsix, url }, function(ok, err)
                if not ok then
                    return fail("download: " .. err)
                end
                run({ "unzip", "-q", vsix, "extension/*", "-d", staging }, function(ok2, err2)
                    if not ok2 then
                        return fail("unzip: " .. err2)
                    end
                    vim.schedule(function()
                        local extracted = vim.fs.joinpath(staging, "extension")
                        local pkg_ok, pkg = pcall(Utils.read_json_file, vim.fs.joinpath(extracted, "package.json"))
                        if not pkg_ok or type(pkg) ~= "table" or pkg.version ~= version then
                            return fail("package.json missing or version mismatch in the downloaded package")
                        end
                        if (pkg.publisher or ""):lower() .. "." .. (pkg.name or ""):lower() ~= M.extension_id then
                            return fail("unexpected package " .. tostring(pkg.publisher) .. "." .. tostring(pkg.name))
                        end

                        local renamed, rename_err = vim.uv.fs_rename(extracted, ext.dir)
                        vim.fn.delete(staging, "rf")
                        if not renamed then
                            return fail("move: " .. tostring(rename_err))
                        end
                        prune(target, version)
                        Utils.info("AL Language extension " .. version .. " installed in " .. target)
                        done(ext, true)
                    end)
                end)
            end)
        end)
    end)
end

return M
