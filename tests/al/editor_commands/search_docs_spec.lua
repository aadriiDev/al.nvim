describe("al.editor_commands.search_docs", function()
    local search_docs
    local orig_open

    before_each(function()
        package.loaded["al.editor_commands.search_docs"] = nil
        search_docs = require("al.editor_commands.search_docs")
        orig_open = vim.ui.open
    end)

    after_each(function()
        vim.ui.open = orig_open
    end)

    it("opens a Microsoft Learn search for the arguments", function()
        local opened
        vim.ui.open = function(url)
            opened = url
        end
        search_docs({ "FindSet", "&", "Next" })
        assert.are.equal(
            "https://learn.microsoft.com/en-us/search/?terms=FindSet%20%26%20Next%20business%20central%20al",
            opened
        )
    end)

    it("uses the word under the cursor without arguments", function()
        local opened
        vim.ui.open = function(url)
            opened = url
        end
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_current_buf(buf)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "    Customer.CalcFields(Balance);" })
        vim.api.nvim_win_set_cursor(0, { 1, 15 })
        search_docs({})
        assert.is_truthy(opened:find("terms=CalcFields%%20", 1, false))
        vim.api.nvim_buf_delete(buf, { force = true })
    end)
end)
