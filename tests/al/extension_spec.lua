describe("al.extension", function()
    local Extension
    local Config
    local root

    ---@param path string
    local function touch(path)
        vim.fn.mkdir(vim.fs.dirname(path), "p")
        local f = assert(io.open(path, "w"))
        f:write("")
        f:close()
    end

    ---@param base string
    ---@param version string
    local function make_ext(base, version)
        local dir = vim.fs.joinpath(base, "ms-dynamics-smb.al-" .. version)
        vim.fn.mkdir(dir, "p")
        return dir
    end

    before_each(function()
        package.loaded["al.extension"] = nil
        Extension = require("al.extension")
        Config = require("al.config")
        root = vim.fn.tempname()
        vim.fn.mkdir(root, "p")
    end)

    after_each(function()
        vim.fn.delete(root, "rf")
    end)

    describe("version_gt", function()
        it("compares numerically, not lexically", function()
            assert.is_true(Extension.version_gt("18.1.2842859", "9.9.9"))
            assert.is_true(Extension.version_gt("18.1.2842859", "18.0.2819426"))
            assert.is_false(Extension.version_gt("18.0.2819426", "18.1.2842859"))
            assert.is_false(Extension.version_gt("18.1.2842859", "18.1.2842859"))
        end)
    end)

    describe("find", function()
        it("returns the highest version in the folder", function()
            make_ext(root, "17.0.1000000")
            make_ext(root, "18.1.2842859")
            make_ext(root, "18.0.2819426")
            vim.fn.mkdir(vim.fs.joinpath(root, "ms-dynamics-smb.al-code-outline-1.0.0"), "p")
            local ext = Extension.find(root)
            assert.are.equal("18.1.2842859", ext.version)
        end)

        it("returns nil when nothing is installed", function()
            assert.is_nil(Extension.find(root))
        end)
    end)

    describe("server", function()
        local name = "Microsoft.Dynamics.Nav.EditorServices.Host"

        it("uses the cross-platform dll shipped since v18", function()
            local dir = make_ext(root, "18.1.2842859")
            touch(vim.fs.joinpath(dir, "bin", name .. ".dll"))
            local server = Extension.server({ dir = dir, version = "18.1.2842859" })
            assert.is_nil(server.native)
            assert.are.equal(vim.fs.joinpath(dir, "bin", name .. ".dll"), server.dll)
        end)

        it("uses the per-platform binaries of older versions", function()
            if vim.fn.has("win32") == 1 then
                return
            end
            local platform = vim.uv.os_uname().sysname:lower():match("darwin") and "darwin" or "linux"
            local dir = make_ext(root, "16.0.1000000")
            touch(vim.fs.joinpath(dir, "bin", platform, name))
            touch(vim.fs.joinpath(dir, "bin", platform, name .. ".dll"))
            local server = Extension.server({ dir = dir, version = "16.0.1000000" })
            assert.are.equal(vim.fs.joinpath(dir, "bin", platform, name), server.native)
            assert.are.equal(vim.fs.joinpath(dir, "bin", platform, name .. ".dll"), server.dll)
        end)
    end)

    describe("server_cmd", function()
        it("starts the dll through dotnet", function()
            local dir = make_ext(root, "18.1.2842859")
            touch(vim.fs.joinpath(dir, "bin", "Microsoft.Dynamics.Nav.EditorServices.Host.dll"))
            Config.setup({ extensionsPath = root, vscodeExtensionsPath = "", dotnetPath = "my-dotnet" })
            local cmd = Extension.server_cmd()
            assert.are.equal("my-dotnet", cmd[1])
            assert.are.equal(vim.fs.joinpath(dir, "bin", "Microsoft.Dynamics.Nav.EditorServices.Host.dll"), cmd[2])
        end)
    end)
end)
