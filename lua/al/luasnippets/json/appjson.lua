-- Snippets for app.json, like the manifest that `AL: Go!` creates:
-- `tappjson` writes a full manifest with a new id, `tdependency` adds an
-- entry to "dependencies". Only offered in files named app.json.

local ls = require("luasnip")
local s = ls.snippet
local sn = ls.snippet_node
local i = ls.insert_node
local f = ls.function_node
local d = ls.dynamic_node
local fmt = require("luasnip.extras.fmt").fmt

local function in_app_json()
    return vim.fn.expand("%:t") == "app.json"
end

--- Random (v4) GUID from libuv's secure random bytes.
local function uuid()
    local bytes = { vim.uv.random(16):byte(1, 16) }
    bytes[7] = bit.bor(bit.band(bytes[7], 0x0f), 0x40)
    bytes[9] = bit.bor(bit.band(bytes[9], 0x3f), 0x80)
    local hex = {}
    for idx, b in ipairs(bytes) do
        hex[#hex + 1] = ("%02x"):format(b)
        if idx == 4 or idx == 6 or idx == 8 or idx == 10 then
            hex[#hex + 1] = "-"
        end
    end
    return table.concat(hex)
end

local function new_id()
    return sn(nil, { i(1, uuid()) })
end

local function project_name()
    return sn(nil, { i(1, vim.fn.expand("%:p:h:t")) })
end

local function publisher()
    local name = vim.trim(vim.fn.system({ "git", "config", "user.name" }))
    return sn(nil, { i(1, vim.v.shell_error == 0 and name ~= "" and name or "Default Publisher") })
end

--- Runtime that goes with the application version: BC26 -> 15.0.
---@param args string[][]
local function runtime(args)
    local major = tonumber((args[1][1] or ""):match("^(%d+)"))
    return major and major > 11 and ("%d.0"):format(major - 11) or "15.0"
end

return {
    s(
        { trig = "tappjson", desc = "app.json manifest", show_condition = in_app_json, condition = in_app_json },
        fmt(
            [[
            {{
              "id": "{}",
              "name": "{}",
              "publisher": "{}",
              "version": "1.0.0.0",
              "brief": "",
              "description": "",
              "privacyStatement": "",
              "EULA": "",
              "help": "",
              "url": "",
              "logo": "",
              "dependencies": [],
              "screenshots": [],
              "platform": "1.0.0.0",
              "application": "{}",
              "idRanges": [
                {{
                  "from": {},
                  "to": {}
                }}
              ],
              "resourceExposurePolicy": {{
                "allowDebugging": true,
                "allowDownloadingSource": true,
                "includeSourceInSymbolFile": true
              }},
              "runtime": "{}",
              "features": ["NoImplicitWith"]
            }}
            ]],
            {
                d(1, new_id),
                d(2, project_name),
                d(3, publisher),
                i(4, "26.0.0.0"),
                i(5, "50100"),
                i(6, "50149"),
                f(runtime, { 4 }),
            }
        )
    ),
    s(
        { trig = "tdependency", desc = "app.json dependency", show_condition = in_app_json, condition = in_app_json },
        fmt(
            [[
            {{
              "id": "{}",
              "name": "{}",
              "publisher": "{}",
              "version": "{}"
            }}
            ]],
            {
                i(1, "00000000-0000-0000-0000-000000000000"),
                i(2, "App Name"),
                i(3, "Publisher"),
                i(4, "1.0.0.0"),
            }
        )
    ),
}
