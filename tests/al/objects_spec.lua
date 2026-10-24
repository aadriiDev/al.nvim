local helpers = require("tests.helpers")

describe("al.objects", function()
    local objects

    --- Creates a project folder with app.json and the given files.
    ---@param tree table<string, string[]>
    ---@param app? table
    local function project(tree, app)
        local root = vim.fn.tempname()
        vim.fn.mkdir(root, "p")
        root = vim.fs.normalize(vim.uv.fs_realpath(root))
        local json = vim.json.encode(app or { idRanges = { { from = 50100, to = 50149 } } })
        vim.fn.writefile({ json }, root .. "/app.json")
        for rel, lines in pairs(tree) do
            vim.fn.mkdir(vim.fs.dirname(root .. "/" .. rel), "p")
            vim.fn.writefile(lines, root .. "/" .. rel)
        end
        return root
    end

    ---@param answers string[] Answers given to vim.ui.input, in order
    local function stub_input(answers)
        local orig = vim.ui.input
        local idx = 0
        vim.ui.input = function(_, cb)
            idx = idx + 1
            cb(answers[idx])
        end
        return function()
            vim.ui.input = orig
        end
    end

    before_each(function()
        package.loaded["al.objects"] = nil
        objects = require("al.objects")
    end)

    describe("next_id", function()
        it("skips ids used by objects of the same type", function()
            local root = project({
                ["src/a.al"] = { "page 50100 A" },
                ["src/b.al"] = { "page 50101 B" },
                ["src/c.al"] = { "table 50102 C" },
            })
            assert.are.equal(50102, objects.next_id(root, "page"))
            assert.are.equal(50100, objects.next_id(root, "table"))
        end)

        it("continues in the next range and accepts idRange", function()
            local root = project({ ["a.al"] = { "codeunit 1 A" } }, {
                idRanges = { { from = 1, to = 1 }, { from = 10, to = 20 } },
            })
            assert.are.equal(10, objects.next_id(root, "codeunit"))
            root = project({}, { idRange = { from = 70000, to = 70010 } })
            assert.are.equal(70000, objects.next_id(root, "codeunit"))
        end)

        it("returns nil when the ranges are full", function()
            local root = project({ ["a.al"] = { "enum 5 A" } }, { idRanges = { { from = 5, to = 5 } } })
            assert.is_nil(objects.next_id(root, "enum"))
        end)
    end)

    describe("table_fields", function()
        it("skips FlowFilters, removed fields and Blob/Media types", function()
            local fields = objects.table_fields({
                'table 50100 "My Table"',
                "{",
                "    fields",
                "    {",
                '        field(1; "No."; Code[20]) { }',
                "        field(2; Description; Text[100])",
                "        {",
                "        }",
                "        field(3; Picture; Media) { }",
                '        field(4; "Date Filter"; Date)',
                "        {",
                "            FieldClass = FlowFilter;",
                "        }",
                "        field(5; Old; Integer)",
                "        {",
                "            ObsoleteState = Removed;",
                "        }",
                '        field(6; Status; Enum "My Status") { }',
                "    }",
                "    keys",
                "    {",
                '        key(PK; "No.") { }',
                "    }",
                "}",
            })
            assert.are.same({ "No.", "Description", "Status" }, vim.tbl_map(function(f)
                return f.name
            end, fields))
        end)
    end)

    describe("render", function()
        local fields = { { id = "1", name = "No.", type = "Code[20]" }, { id = "2", name = "Name", type = "Text[100]" } }

        it("builds a list page from a table", function()
            local lines = objects.render({ type = "page", id = 50100, name = "Customer List", base = "My Customer", page_type = "List", fields = fields })
            local text = table.concat(lines, "\n")
            assert.are.equal('page 50100 "Customer List"', lines[1])
            assert.is_truthy(text:find('SourceTable = "My Customer";', 1, true))
            assert.is_truthy(text:find("ApplicationArea = All;", 1, true))
            assert.is_truthy(text:find("UsageCategory = Lists;", 1, true))
            assert.is_truthy(text:find("repeater(General)", 1, true))
            assert.is_truthy(text:find('field("No."; Rec."No.")', 1, true))
            assert.is_truthy(text:find("ToolTip = 'Specifies the value of the No. field.';", 1, true))
            assert.is_truthy(text:find("field(Name; Rec.Name)", 1, true))
        end)

        it("indents the page layout", function()
            local lines = objects.render({ type = "page", id = 1, name = "C", base = "T", page_type = "Card", fields = fields })
            local from = vim.fn.index(lines, "        area(Content)") + 1
            assert.are.same({
                "        area(Content)",
                "        {",
                "            group(General)",
                "            {",
                "                Caption = 'General';",
                '                field("No."; Rec."No.")',
                "                {",
            }, vim.list_slice(lines, from, from + 6))
        end)

        it("builds a card page with a General group", function()
            local text = table.concat(objects.render({ type = "page", id = 1, name = "C", base = "T", page_type = "Card", fields = fields }), "\n")
            assert.is_truthy(text:find("PageType = Card;", 1, true))
            assert.is_truthy(text:find("group(General)", 1, true))
            assert.is_nil(text:find("UsageCategory", 1, true))
        end)

        it("builds reports, queries and xmlports with a column per field", function()
            local report = table.concat(objects.render({ type = "report", id = 1, name = "R", base = "Sales Line", fields = fields }), "\n")
            assert.is_truthy(report:find('dataitem(SalesLine; "Sales Line")', 1, true))
            assert.is_truthy(report:find('column(No; "No.") { }', 1, true))
            local xmlport = table.concat(objects.render({ type = "xmlport", id = 1, name = "X", base = "Item", fields = fields }), "\n")
            assert.is_truthy(xmlport:find("tableelement(Item; Item)", 1, true))
            assert.is_truthy(xmlport:find('fieldelement(No; Item."No.") { }', 1, true))
        end)

        it("declares extensions and objects without id", function()
            assert.are.equal(
                'pageextension 50100 "Cust Card Ext" extends "Customer Card"',
                objects.render({ type = "pageextension", id = 50100, name = "Cust Card Ext", base = "Customer Card" })[1]
            )
            assert.are.equal("interface IShipping", objects.render({ type = "interface", name = "IShipping" })[1])
        end)

        it("starts with the namespace when given", function()
            local lines = objects.render({ type = "codeunit", id = 1, name = "C", namespace = "Abc.Sales" })
            assert.are.same({ "namespace Abc.Sales;", "", "codeunit 1 C" }, vim.list_slice(lines, 1, 3))
        end)

        it("builds a card page when there is no source table", function()
            local text = table.concat(objects.render({ type = "page", id = 1, name = "P", page_type = "List" }), "\n")
            assert.is_truthy(text:find("PageType = Card;", 1, true))
            assert.is_nil(text:find("repeater", 1, true))
        end)

        it("gives a query without fields a SystemId column", function()
            local text = table.concat(objects.render({ type = "query", id = 1, name = "Q", base = "Item" }), "\n")
            assert.is_truthy(text:find("column(SystemId; SystemId) { }", 1, true))
        end)

        it("can put ApplicationArea on every field", function()
            local Config = require("al.config")
            Config.objects.application_area_on_fields = true
            local lines = objects.render({ type = "page", id = 1, name = "P", base = "T", page_type = "List", fields = fields })
            Config.objects.application_area_on_fields = false
            local count = select(2, table.concat(lines, "\n"):gsub("ApplicationArea = All;", ""))
            assert.are.equal(2, count)
        end)
    end)

    describe("commands", function()
        it("newObject creates the file with the next id and opens it", function()
            local root = project({ ["src/a.al"] = { "codeunit 50100 A" } })
            vim.cmd.edit(root .. "/app.json")
            local restore = stub_input({ "Sales Post" })
            local notify = helpers.capture_notify()
            objects.new_object("codeunit")
            local path = root .. "/src/SalesPost.Codeunit.al"
            assert.is_not_nil(vim.uv.fs_stat(path))
            assert.are.equal('codeunit 50101 "Sales Post"', vim.fn.readfile(path)[1])
            assert.are.equal(path, vim.fs.normalize(vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0))))
            restore()
            notify.restore()
            vim.cmd("silent! %bwipeout!")
        end)

        it("createListPage builds a page from the table in the buffer", function()
            local root = project({
                ["src/table/MyItem.Table.al"] = {
                    "namespace My.App;",
                    'table 50100 "My Item"',
                    "{",
                    "    fields",
                    "    {",
                    '        field(1; "No."; Code[20]) { }',
                    "    }",
                    "}",
                },
            })
            vim.cmd.edit(root .. "/src/table/MyItem.Table.al")
            local restore = stub_input({ "My Item List" })
            local notify = helpers.capture_notify()
            objects.from_table("page", "List")
            local path = root .. "/src/page/MyItemList.Page.al"
            assert.is_not_nil(vim.uv.fs_stat(path))
            local text = table.concat(vim.fn.readfile(path), "\n")
            assert.is_truthy(text:find('SourceTable = "My Item";', 1, true))
            assert.is_truthy(text:find('field("No."; Rec."No.")', 1, true))
            assert.is_truthy(text:find("namespace My.App;", 1, true))
            restore()
            notify.restore()
            vim.cmd("silent! %bwipeout!")
        end)

        it("rejects names over 30 characters", function()
            local root = project({})
            vim.cmd.edit(root .. "/app.json")
            local restore = stub_input({ string.rep("x", 31) })
            local notify = helpers.capture_notify()
            objects.new_object("table")
            assert.is_truthy(notify.messages[1].msg:match("30 characters"))
            restore()
            notify.restore()
            vim.cmd("silent! %bwipeout!")
        end)
    end)
end)
