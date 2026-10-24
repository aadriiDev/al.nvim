local Extension = require("al.extension")

-- Installs (or updates to) the latest AL Language extension and points the
-- language server at it.
local install_extension = function()
    Extension.install({
        on_done = function(ext, updated)
            if not ext or not updated then
                return
            end
            -- Rebuild the al_ls config so its cmd uses the newly installed version
            require("al.lsp").setup()
            if require("al.integrations").loaded.luasnip then
                require("al.integrations.luasnip").load_extension_snippets()
            end
            if #vim.lsp.get_clients({ name = "al_ls" }) > 0 then
                require("al.editor_commands.restart_lsp")()
            end
        end,
    })
end

return install_extension
