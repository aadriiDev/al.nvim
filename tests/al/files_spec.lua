local helpers = require("tests.helpers")

describe("al.files", function()
    local files
    local Config = require("al.config")

    ---@param overrides? table
    local function settings(overrides)
        return vim.tbl_extend("force", vim.deepcopy(Config.files), overrides or {})
    end

    --- Creates a project folder with app.json and the given files.
    ---@param tree table<string, string[]>
    local function project(tree)
        local root = vim.fn.tempname()
        vim.fn.mkdir(root, "p")
        root = vim.fs.normalize(vim.uv.fs_realpath(root))
        vim.fn.writefile({ "{}" }, root .. "/app.json")
        for rel, lines in pairs(tree) do
            vim.fn.mkdir(vim.fs.dirname(root .. "/" .. rel), "p")
            vim.fn.writefile(lines, root .. "/" .. rel)
        end
        return root
    end

    before_each(function()
        package.loaded["al.files"] = nil
        files = require("al.files")
    end)

    describe("parse", function()
        it("reads type, id, name and namespace", function()
            local obj = files.parse({
                "// table 1 Ignored",
                "namespace My.App.Sales;",
                "",
                'table 50100 "My Table"',
                "{",
            })
            assert.are.equal("table", obj.type)
            assert.are.equal("50100", obj.id)
            assert.are.equal("My Table", obj.name)
            assert.are.equal("My.App.Sales", obj.namespace)
            assert.are.equal(4, obj.line)
        end)

        it("reads unquoted names and the extended object", function()
            local obj = files.parse({ 'pageextension 50100 CustCardExt Extends "Customer Card" // 21' })
            assert.are.equal("CustCardExt", obj.name)
            assert.are.equal("Customer Card", obj.base_name)
            assert.are.equal("21", obj.base_id)
        end)

        it("reads objects without id", function()
            local obj = files.parse({ 'interface "IMy Interface"' })
            assert.are.equal("interface", obj.type)
            assert.are.equal("IMy Interface", obj.name)
        end)

        it("detects test codeunits", function()
            local obj = files.parse({ "codeunit 50150 MyTests", "{", "    Subtype = Test;", "}" })
            assert.is_true(obj.test)
        end)

        it("returns nil without an object", function()
            assert.is_nil(files.parse({ "// nothing here" }))
        end)
    end)

    describe("file_name", function()
        it("follows the AA0215 pattern by default", function()
            local obj = files.parse({ 'table 50100 "Sales Header_Ext."' })
            assert.are.equal("SalesHeaderExt.Table.al", files.file_name(obj, settings()))
        end)

        it("uses the extension pattern for extension objects", function()
            local obj = files.parse({ 'tableextension 50100 "My Customer" extends Customer // 18' })
            local s = settings({ pattern_extensions = "<ObjectTypeShort><BaseId>-Ext<ObjectId>.<ObjectNameShort>.al" })
            assert.are.equal("Tab18-Ext50100.MyCustomer.al", files.file_name(obj, s))
        end)

        it("adds the prefix to the name and can drop it from the file name", function()
            local obj = files.parse({ 'page 50100 "Customer List"' })
            assert.are.equal("ABCCustomerList.Page.al", files.file_name(obj, settings({ object_name_prefix = "ABC" })))
            local s = settings({ object_name_prefix = "ABC", remove_prefix_from_filename = true })
            assert.are.equal("CustomerList.Page.al", files.file_name(obj, s))
        end)
    end)

    describe("target_dir", function()
        it("uses subfolder and object type", function()
            local obj = files.parse({ "report 50100 MyReport" })
            assert.are.equal("/p/src/report", files.target_dir(obj, settings(), "/p"))
        end)

        it("uses the namespace when asked", function()
            local obj = files.parse({ "namespace Abc.Sales.Posting;", "codeunit 50100 Post" })
            local s = settings({ by_namespace = true, namespace_prefix_to_ignore = "Abc" })
            assert.are.equal("/p/src/Sales/Posting", files.target_dir(obj, s, "/p"))
        end)

        it("puts test codeunits in test/", function()
            local obj = files.parse({ "codeunit 50150 MyTests", "{", "Subtype = Test;" })
            assert.are.equal("/p/test", files.target_dir(obj, settings(), "/p"))
        end)
    end)

    describe("settings", function()
        it("reads CRS settings from .vscode/settings.json with comments", function()
            local root = project({
                [".vscode/settings.json"] = {
                    "{",
                    "  // CRS",
                    '  "CRS.FileNamePattern": "<ObjectTypeShort><ObjectId>.<ObjectNameShort>.al",',
                    '  "CRS.OnSaveAlFileAction": "Reorganize",',
                    '  "CRS.ObjectNamePrefix": "ABC",',
                    "}",
                },
            })
            local s = files.settings(root)
            assert.are.equal("<ObjectTypeShort><ObjectId>.<ObjectNameShort>.al", s.pattern)
            assert.are.equal("reorganize", s.on_save)
            assert.are.equal("ABC", s.object_name_prefix)
            assert.are.equal("src", s.subfolder)
        end)
    end)

    describe("process", function()
        it("renames a file on disk", function()
            local root = project({ ["src/old.al"] = { 'table 50100 "My Table"', "{", "}" } })
            local new_path = files.process(root .. "/src/old.al", "rename")
            assert.are.equal(root .. "/src/MyTable.Table.al", new_path)
            assert.is_nil(vim.uv.fs_stat(root .. "/src/old.al"))
            assert.is_not_nil(vim.uv.fs_stat(new_path))
        end)

        it("reorganizes into subfolder/type", function()
            local root = project({ ["old.al"] = { "page 50100 MyPage" } })
            local new_path = files.process(root .. "/old.al", "reorganize")
            assert.are.equal(root .. "/src/page/MyPage.Page.al", new_path)
        end)

        it("refuses to overwrite an existing file", function()
            local root = project({
                ["src/a.al"] = { "page 50100 MyPage" },
                ["src/MyPage.Page.al"] = { "page 50101 MyPage" },
            })
            local new_path, err = files.process(root .. "/src/a.al", "rename")
            assert.is_nil(new_path)
            assert.is_truthy(err:match("already exists"))
        end)

        it("adds the object name prefix in the file", function()
            local root = project({
                [".vscode/settings.json"] = { '{ "CRS.ObjectNamePrefix": "ABC " }' },
                ["src/a.al"] = { 'codeunit 50100 "Post Stuff"', "{", "}" },
            })
            local new_path = files.process(root .. "/src/a.al", "rename")
            assert.are.equal(root .. "/src/ABCPostStuff.Codeunit.al", new_path)
            assert.are.equal('codeunit 50100 "ABC Post Stuff"', vim.fn.readfile(new_path)[1])
        end)

        it("moves the open buffer to the new path", function()
            local root = project({ ["src/a.al"] = { "query 50100 MyQuery" } })
            vim.cmd.edit(root .. "/src/a.al")
            local buf = vim.api.nvim_get_current_buf()
            local notify = helpers.capture_notify()
            files.current("rename")
            assert.are.equal(root .. "/src/MyQuery.Query.al", vim.fs.normalize(vim.api.nvim_buf_get_name(buf)))
            assert.is_false(vim.bo[buf].modified)
            for _, b in ipairs(vim.api.nvim_list_bufs()) do
                assert.are_not.equal(root .. "/src/a.al", vim.fs.normalize(vim.api.nvim_buf_get_name(b)))
            end
            notify.restore()
            vim.api.nvim_buf_delete(buf, { force = true })
        end)
    end)

    describe("on save", function()
        it("renames the file when CRS.OnSaveAlFileAction is Rename", function()
            local root = project({
                [".vscode/settings.json"] = { '{ "CRS.OnSaveAlFileAction": "Rename" }' },
                ["src/a.al"] = { "enum 50100 MyEnum", "{", "}" },
            })
            files.setup()
            vim.cmd.edit(root .. "/src/a.al")
            local buf = vim.api.nvim_get_current_buf()
            vim.cmd("silent write")
            assert.are.equal(root .. "/src/MyEnum.Enum.al", vim.fs.normalize(vim.api.nvim_buf_get_name(buf)))
            assert.is_nil(vim.uv.fs_stat(root .. "/src/a.al"))
            vim.api.nvim_buf_delete(buf, { force = true })
            vim.api.nvim_del_augroup_by_name("al-files")
        end)
    end)

    describe("project_files", function()
        it("skips hidden folders", function()
            local root = project({
                ["src/a.al"] = { "page 1 A" },
                [".snapshots/b.al"] = { "page 2 B" },
            })
            assert.are.same({ root .. "/src/a.al" }, files.project_files(root))
        end)
    end)
end)
