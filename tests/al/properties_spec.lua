local helpers = require("tests.helpers")

describe("al.properties", function()
    local properties

    before_each(function()
        package.loaded["al.properties"] = nil
        properties = require("al.properties")
    end)

    describe("tooltips", function()
        it("adds ToolTips to page fields and actions that miss one", function()
            local lines, added = properties.apply({
                'page 50100 "My List"',
                "{",
                "    layout",
                "    {",
                "        area(Content)",
                "        {",
                "            repeater(General)",
                "            {",
                '                field("No."; Rec."No.")',
                "                {",
                "                    ApplicationArea = All;",
                "                }",
                "                field(Desc; Rec.Description) { }",
                "                field(Total; Rec.Amount)",
                "                {",
                "                    ToolTip = 'Already here.';",
                "                }",
                "                field(Other; Rec.Other)",
                "            }",
                "        }",
                "    }",
                "    actions",
                "    {",
                "        area(Processing)",
                "        {",
                "            action(Post)",
                "            {",
                "                trigger OnAction()",
                "                begin",
                "                end;",
                "            }",
                "        }",
                "    }",
                "}",
            }, "tooltips")
            assert.are.equal(4, added)
            assert.are.same({
                '                field("No."; Rec."No.")',
                "                {",
                "                    ToolTip = 'Specifies the value of the No. field.';",
                "                    ApplicationArea = All;",
                "                }",
                "                field(Desc; Rec.Description)",
                "                {",
                "                    ToolTip = 'Specifies the value of the Description field.';",
                "                }",
                "                field(Total; Rec.Amount)",
                "                {",
                "                    ToolTip = 'Already here.';",
                "                }",
                "                field(Other; Rec.Other)",
                "                {",
                "                    ToolTip = 'Specifies the value of the Other field.';",
                "                }",
            }, vim.list_slice(lines, 9, 25))
            assert.are.same({ "            action(Post)", "            {", "                ToolTip = 'Executes the Post action.';" }, vim.list_slice(lines, 33, 35))
        end)

        it("keeps other properties of an inline body and does nothing twice", function()
            local lines, added = properties.apply({
                "pageextension 50100 Ext extends \"Customer Card\"",
                "{",
                "    layout",
                "    {",
                "        addlast(General)",
                "        {",
                "            field(Score; Rec.Score) { Editable = false; }",
                "        }",
                "    }",
                "}",
            }, "tooltips")
            assert.are.equal(1, added)
            assert.are.same({
                "            field(Score; Rec.Score)",
                "            {",
                "                ToolTip = 'Specifies the value of the Score field.';",
                "                Editable = false;",
                "            }",
            }, vim.list_slice(lines, 7, 11))
            local _, again = properties.apply(lines, "tooltips")
            assert.are.equal(0, again)
        end)

        it("skips API pages and other object types", function()
            local _, added = properties.apply({ "page 1 Api", "{", "    PageType = API;", "    field(a; Rec.A) { }", "}" }, "tooltips")
            assert.are.equal(0, added)
            _, added = properties.apply({ "table 1 T", "{", '    field(1; "No."; Code[20]) { }', "}" }, "tooltips")
            assert.are.equal(0, added)
        end)

        it("escapes quotes and keeps CRLF line endings", function()
            local lines = properties.apply({ "page 1 P\r", "{\r", "    field(x; Rec.\"Cust's No.\") { }\r", "}\r" }, "tooltips")
            assert.are.equal("        ToolTip = 'Specifies the value of the Cust''s No. field.';\r", lines[5])
        end)
    end)

    describe("captions", function()
        it("adds Captions to table fields named after the field", function()
            local lines, added = properties.apply({
                'table 50100 "My Table"',
                "{",
                "    fields",
                "    {",
                '        field(1; "No."; Code[20])',
                "        {",
                "            Caption = 'Number';",
                "        }",
                "        field(2; Description; Text[100])",
                "        {",
                "            DataClassification = CustomerContent;",
                "        }",
                "    }",
                "}",
            }, "captions")
            assert.are.equal(1, added)
            assert.are.equal("            Caption = 'Description';", lines[11])
            assert.are.equal("            DataClassification = CustomerContent;", lines[12])
        end)

        it("does not count captions of nested blocks", function()
            local _, added = properties.apply({
                "tableextension 1 E extends Customer",
                "{",
                "    fields",
                "    {",
                "        field(50100; Score; Integer)",
                "        {",
                "            trigger OnValidate()",
                "            begin",
                "            end;",
                "        }",
                "    }",
                "}",
            }, "captions")
            assert.are.equal(1, added)
        end)
    end)

    describe("command", function()
        it("works on the current buffer", function()
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_set_current_buf(buf)
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "table 1 T", "{", "    fields", "    {", "        field(1; A; Integer) { }", "    }", "}" })
            local notify = helpers.capture_notify()
            properties.command("captions")
            assert.is_truthy(notify.messages[1].msg:match("Added 1 Captions"))
            assert.are.equal("            Caption = 'A';", vim.api.nvim_buf_get_lines(buf, 6, 7, false)[1])
            notify.restore()
            vim.api.nvim_buf_delete(buf, { force = true })
        end)

        it("works on every file of the project", function()
            local root = vim.fn.tempname()
            vim.fn.mkdir(root .. "/src", "p")
            root = vim.fs.normalize(vim.uv.fs_realpath(root))
            vim.fn.writefile({ "{}" }, root .. "/app.json")
            vim.fn.writefile({ "page 1 P", "{", "    field(a; Rec.A) { }", "}" }, root .. "/src/P.Page.al")
            vim.fn.writefile({ "page 2 Q", "{", "    field(b; Rec.B) { }", "}" }, root .. "/src/Q.Page.al")
            vim.cmd.edit(root .. "/app.json")
            local notify = helpers.capture_notify()
            properties.command("tooltips", "project")
            assert.is_truthy(notify.messages[1].msg:match("Added 2 ToolTips in 2 files"))
            assert.are.equal("        ToolTip = 'Specifies the value of the B field.';", vim.fn.readfile(root .. "/src/Q.Page.al")[5])
            notify.restore()
            vim.cmd("silent! %bwipeout!")
        end)
    end)
end)
