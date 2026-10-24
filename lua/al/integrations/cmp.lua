local M = {}

M.setup = function()
    local ok, cmp = pcall(require, "cmp")
    if not ok then
        return
    end
    cmp.register_source("al_var", require("al.cmp_source").new())
end

return M
