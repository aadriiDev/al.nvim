---@class al.Config.mod: al.Config
local M = {}

---@alias al.LSP.LogLevel "Debug" | "Verbose" | "Normal" | "Warning" | "Error"
---@alias al.LSP.TelemetryLevel "none" | "crash" | "error" | "all"
---@alias al.LSP.Browser "SystemDefault" | "Chrome" | "Firefox" | "Edge" | "EdgeBeta"

---@class al.Config.LSP
---@field telemetryLevel al.LSP.TelemetryLevel
---@field browser al.LSP.Browser
---@field inlayHintsParameterNames boolean
---@field inlayHintsFunctionReturnTypes boolean
---@field semanticFolding boolean
---@field extendGoToSymbolInWorkspace boolean
---@field extendGoToSymbolInWorkspaceResultLimit integer
---@field extendGoToSymbolInWorkspaceIncludeSymbolFiles boolean
---@field log {path: string, level: al.LSP.LogLevel }

---@class al.Config.Multiproject
---@field settings_path string
---@field closure_timeout_ms integer

---@class al.Config
---@field lsp al.Config.LSP
---@field multiproject al.Config.Multiproject
---@field files al.Config.Files
---@field variables al.Config.Variables
---@field objects al.Config.Objects
---@field snippets { crs: boolean }
---@field extensionsPath string
---@field vscodeExtensionsPath string
---@field dotnetPath string
---@field extensionPrerelease boolean
local defaults = {
    -- Where `:AL installExtension` installs the AL Language extension.
    -- Searched first; vscodeExtensionsPath is used as a fallback.
    extensionsPath = vim.fn.stdpath("data") .. "/al-extension",
    vscodeExtensionsPath = "~\\.vscode\\extensions\\",
    -- .NET host used to start the language server (extension v18+ ships a .dll)
    dotnetPath = "dotnet",
    -- Let `:AL installExtension` pick Marketplace pre-release versions
    extensionPrerelease = false,
    integrations = {
        luasnip = true,
        treesitter = true,
        -- Registers the "al_var" nvim-cmp source (variable names from the type)
        cmp = true,
    },
    workspace = {
        alResourceConfigurationSettings = {
            assemblyProbingPaths = {
                "./.netpackages",
            },
            codeAnalyzers = {
                "${CodeCop}",
                "${analyzerFolder}BusinessCentral.LinterCop.dll",
            },
            enableCodeAnalysis = true,
            backgroundCodeAnalysis = true,
            packageCachePaths = {
                "./.alpackages",
            },
            ruleSetPath = ".vscode/ruleset.json",
            enableCodeActions = true,
            incrementalBuild = false,
            outputAnalyzerStatistics = false,
            enableExternalRulesets = true,
        },
    },
    lsp = {
        telemetryLevel = "all",
        browser = "SystemDefault",
        inlayHintsParameterNames = true,
        inlayHintsFunctionReturnTypes = true,
        semanticFolding = true,
        extendGoToSymbolInWorkspace = true,
        extendGoToSymbolInWorkspaceResultLimit = 100,
        extendGoToSymbolInWorkspaceIncludeSymbolFiles = true,
        log = {
            path = "",
            level = "Normal",
        },
    },
    multiproject = {
        settings_path = ".vscode/settings.json",
        closure_timeout_ms = 300000, -- 5 minutes; increase for very large workspaces
    },
    -- :AL renameFile / reorganizeFile, same patterns as the CRS AL Language
    -- extension. Variables: <ObjectType>, <ObjectTypeShort>,
    -- <ObjectTypeShortPascalCase>, <ObjectTypeShortUpper>, <ObjectId>,
    -- <ObjectName>, <ObjectNameShort>, <BaseName>, <BaseNameShort>, <BaseId>,
    -- <Prefix>, <Suffix>. The default follows the AA0215 best practice.
    files = {
        pattern = "<ObjectNameShort>.<ObjectTypeShortPascalCase>.al",
        pattern_extensions = "<ObjectNameShort>.<ObjectTypeShortPascalCase>.al",
        pattern_page_customizations = "<ObjectNameShort>.<ObjectTypeShortPascalCase>.al",
        subfolder = "src", -- "None" disables reorganize
        on_save = "none", -- "none" | "rename" | "reorganize"
        use_git_mv = false,
        by_namespace = false,
        namespace_prefix_to_ignore = "",
        object_name_prefix = "",
        object_name_suffix = "",
        remove_prefix_from_filename = false,
        remove_suffix_from_filename = false,
        remove_underscore_from_filename = true,
        -- CRS.* keys in the project's .vscode/settings.json override these
        read_crs_settings = true,
    },
    snippets = {
        -- Design pattern, test, upgrade and FlowField snippets from the CRS AL
        -- Language extension (triggers end in "waldo": ttestcasewaldo...)
        crs = true,
    },
    -- :AL newObject and the create*FromTable wizards
    objects = {
        application_area = "All",
        -- false: one ApplicationArea on the page/report; true: on every field
        application_area_on_fields = false,
        field_tooltip = "Specifies the value of the %1 field.",
        action_tooltip = "Executes the %1 action.",
        list_usage_category = "Lists",
    },
    -- Variable names suggested from the type (al_var cmp source, v* snippets).
    -- files.object_name_prefix/suffix are always ignored too.
    variables = {
        ignore_prefixes = {},
        ignore_suffixes = {},
    },
}

---@class al.LaunchConfiguration
M.default_launch_cfg = {
    name = "",
    type = "al",
    request = "launch",
    publishOnly = false,
    isRad = false,
    justDebug = false,
    -- Core server connection settings
    server = "http://bcserver",
    port = 7049,
    serverInstance = "",
    tenant = "default",
    primaryTenantDomain = "",
    applicationFamily = "",
    authentication = "MicrosoftEntraID",
    -- Startup object settings
    startupObjectId = 22,
    startupObjectType = "Page",
    startupCompany = "",
    -- Schema and publishing settings
    schemaUpdateMode = "Synchronize",
    dependencyPublishingOption = "Default",
    forceUpgrade = false,
    useSystemSessionForDeployment = false,
    -- Debugging settings
    breakOnError = "All",
    breakOnErrorBehaviour = false, -- Keep for backward compatibility
    breakOnRecordWrite = false,
    enableSqlInformationDebugger = true,
    enableLongRunningSqlStatements = true,
    longRunningSqlStatementsThreshold = 500,
    numberOfSqlStatements = 10,
    -- Browser and URL settings
    launchBrowser = true,
    usePublicURLFromServer = true,
    validateServerCertificate = true,
    -- Environment settings
    environmentName = "",
    environmentType = nil, -- Can be "OnPrem", "Sandbox", or "Production"
    sandboxName = "", -- Deprecated but kept for compatibility
    -- Network and timeout settings
    disableHttpRequestTimeout = false,
    -- Snapshot settings
    snapshotFileName = "",
    -- Legacy/compatibility settings
    projectReferenceDefinitions = {},
    useInteractiveLogin = true,
    isResolved = true,
}

M.language_extension_version = ""

---@type al.Config
local options

---@param opts? al.Config
function M.setup(opts)
    ---@type al.Config
    options = vim.tbl_deep_extend("force", {}, options or defaults, opts or {})

    vim.api.nvim_create_user_command("AL", function(...)
        require("al.cmd").execute(...)
    end, {
        nargs = "*",
        complete = function(...)
            return require("al.cmd").complete(...)
        end,
        desc = "al.nvim",
    })

    if not vim.g._al_testing then
        vim.schedule(function()
            require("al.lsp").setup()
            pcall(function()
                require("al.debugger").setup()
            end)
            require("al.buf").setup()
            require("al.integrations").setup()
            require("al.multiproject").setup()
            require("al.files").setup()
        end)
    end
    return options
end

return setmetatable(M, {
    __index = function(_, key)
        options = options or M.setup()
        return options[key]
    end,
})
