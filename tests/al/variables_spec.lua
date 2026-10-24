local helpers = require("tests.helpers")

describe("al.variables", function()
    local variables

    ---@param lines string[]
    ---@param cursor? integer[]
    local function buffer(lines, cursor)
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_current_buf(buf)
        vim.bo[buf].expandtab = true
        vim.bo[buf].shiftwidth = 4
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        if cursor then
            vim.api.nvim_win_set_cursor(0, cursor)
        end
        return buf
    end

    before_each(function()
        package.loaded["al.variables"] = nil
        variables = require("al.variables")
    end)

    describe("parse_declaration", function()
        it("reads name, type and object", function()
            local d = variables.parse_declaration('        SalesHeader: Record "Sales Header";')
            assert.are.equal("SalesHeader", d.name)
            assert.are.equal(8, d.name_start)
            assert.are.equal(19, d.name_end)
            assert.are.equal("Record", d.kind)
            assert.are.equal("Sales Header", d.object)
            assert.is_false(d.temporary)
        end)

        it("handles an empty name, temporary and namespaces", function()
            local d = variables.parse_declaration("    : record Microsoft.Sales.Customer.Customer temporary;")
            assert.are.equal("", d.name)
            assert.are.equal("Customer", d.object)
            assert.is_true(d.temporary)
        end)

        it("ignores simple types", function()
            assert.is_nil(variables.parse_declaration("    Counter: Integer;"))
        end)
    end)

    describe("suggest", function()
        it("returns full, abbreviated and capitals names", function()
            assert.are.same({ "SalesHeader", "SalesHdr", "SH" }, variables.suggest("Sales Header"))
        end)

        it("abbreviates phrases", function()
            assert.are.same({ "GLEntry", "GLE" }, variables.suggest("G/L Entry"))
            local names = variables.suggest("General Ledger Setup")
            assert.are.same({ "GeneralLedgerSetup", "GLSetup" }, vim.list_slice(names, 1, 2))
        end)

        it("prefixes temporary records with Temp (AA0073)", function()
            assert.are.equal("TempCustomer", variables.suggest("Customer", true)[1])
        end)

        it("drops configured prefixes", function()
            local Config = require("al.config")
            local saved = Config.variables.ignore_prefixes
            Config.variables.ignore_prefixes = { "ABC " }
            assert.are.equal("CustomerExt", variables.suggest("ABC Customer Ext")[1])
            Config.variables.ignore_prefixes = saved
        end)
    end)

    describe("sort", function()
        it("orders declarations as AA0021 expects and keeps the rest in place", function()
            local buf = buffer({
                "codeunit 50100 Test",
                "{",
                "    procedure Run()",
                "    var",
                "        Counter: Integer;",
                "        // the page",
                "        CustomerCard: Page \"Customer Card\";",
                "        MyLbl: Label 'Hello',",
                "            Comment = 'greeting';",
                "        Customer: Record Customer;",
                "        Name: Text[100];",
                "",
                "    begin",
                "    end;",
                "}",
            })
            assert.are.equal(1, variables.sort(buf))
            assert.are.same({
                "        Customer: Record Customer;",
                "        // the page",
                "        CustomerCard: Page \"Customer Card\";",
                "        Counter: Integer;",
                "        MyLbl: Label 'Hello',",
                "            Comment = 'greeting';",
                "        Name: Text[100];",
                "",
                "    begin",
            }, vim.api.nvim_buf_get_lines(buf, 4, 13, false))
            assert.are.equal(0, variables.sort(buf))
            vim.api.nvim_buf_delete(buf, { force = true })
        end)

        it("leaves sections with preprocessor directives alone", function()
            local lines = {
                "    var",
                "        A: Integer;",
                "#if CLEAN25",
                "        B: Record Customer;",
                "#endif",
                "    begin",
            }
            local buf = buffer(lines)
            assert.are.equal(0, variables.sort(buf))
            assert.are.same(lines, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
            vim.api.nvim_buf_delete(buf, { force = true })
        end)
    end)

    describe("goto", function()
        local lines = {
            "codeunit 50100 Test",
            "{",
            "    var",
            "        Global: Integer;",
            "",
            "    procedure WithVars()",
            "    var",
            "        X: Integer;",
            "    begin",
            "        if true then begin",
            "        end;",
            "        X := 1;",
            "    end;",
            "",
            "    local procedure NoVars()",
            "    begin",
            "        Message('');",
            "    end;",
            "}",
        }

        it("jumps to the local var section, past inner blocks", function()
            local buf = buffer(lines, { 12, 0 })
            variables.goto_local()
            assert.are.same({ 8, #lines[8] - 1 }, vim.api.nvim_win_get_cursor(0))
            vim.api.nvim_buf_delete(buf, { force = true })
        end)

        it("adds a var section when the procedure has none", function()
            local buf = buffer(lines, { 17, 0 })
            variables.goto_local()
            assert.are.same({ "    var", "        " }, vim.api.nvim_buf_get_lines(buf, 15, 17, false))
            assert.are.equal(17, vim.api.nvim_win_get_cursor(0)[1])
            vim.api.nvim_buf_delete(buf, { force = true })
        end)

        it("jumps to the global var section", function()
            local buf = buffer(lines, { 17, 0 })
            variables.goto_global()
            assert.are.same({ 4, #lines[4] - 1 }, vim.api.nvim_win_get_cursor(0))
            vim.api.nvim_buf_delete(buf, { force = true })
        end)

        it("warns outside a procedure", function()
            local buf = buffer(lines, { 4, 0 })
            local notify = helpers.capture_notify()
            variables.goto_local()
            assert.is_truthy(notify.messages[1].msg:match("not inside a procedure"))
            notify.restore()
            vim.api.nvim_buf_delete(buf, { force = true })
        end)
    end)

    describe("cmp source", function()
        it("offers names for the declaration under the cursor", function()
            local source = require("al.cmp_source").new()
            local line = '        v: Record "Sales Header" temporary;'
            local result
            source:complete({
                context = { cursor_line = line, cursor = { row = 3, col = 10 } },
            }, function(r)
                result = r
            end)
            assert.are.same({ "TempSalesHeader", "TempSalesHdr", "TempSH" }, vim.tbl_map(function(item)
                return item.label
            end, result.items))
            assert.are.same({ line = 2, character = 8 }, result.items[1].textEdit.range.start)
            assert.are.same({ line = 2, character = 9 }, result.items[1].textEdit.range["end"])
        end)

        it("offers nothing outside the name", function()
            local source = require("al.cmp_source").new()
            local result
            source:complete({
                context = { cursor_line = "        X: Record Customer;", cursor = { row = 1, col = 20 } },
            }, function(r)
                result = r
            end)
            assert.are.same({}, result.items)
        end)
    end)
end)
