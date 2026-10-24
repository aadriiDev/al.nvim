local Util = require("al.utils")

-- Opens a Microsoft Learn search for Business Central development, like the
-- CRS "Search Microsoft Docs" command.
local base_url = "https://learn.microsoft.com/en-us/search/?terms="

---@param s string
---@return string
local function url_encode(s)
    return (s:gsub("[^%w%-%._~]", function(c)
        return ("%%%02X"):format(c:byte())
    end))
end

--- Search terms: the command arguments, else the word under the cursor.
---@param args string[]
---@return string
local function terms(args)
    if args and #args > 0 and table.concat(args, "") ~= "" then
        return table.concat(args, " ")
    end
    return vim.fn.expand("<cword>")
end

---@param args string[]
local search_docs = function(args)
    local query = vim.trim(terms(args))
    if query == "" then
        Util.error("Nothing to search for.")
        return
    end
    local url = base_url .. url_encode(query .. " business central al")
    local ok, err = pcall(vim.ui.open, url)
    if not ok then
        Util.error("Could not open the browser: " .. tostring(err))
    end
    return url
end

return search_docs
