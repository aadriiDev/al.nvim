# al.nvim

Full AL language support for Neovim — LSP, debugging, build commands, and
multi-project workspaces for Microsoft Dynamics 365 Business Central.

## Features

- **LSP integration** — code completion, diagnostics, go-to-definition, inlay
  hints, and semantic folding via the AL Language Server (from the AL Language
  extension, installed with `:AL installExtension` — VS Code not required)
- **Multi-project workspaces** — open `.code-workspace` files containing
  multiple AL projects with full project-reference closure support (requires
  [code-workspace.nvim])
- **Debugging** — nvim-dap adapter with a cross-platform Go proxy that solves
  stdio handle issues with AL EditorServices
- **Build system** — `:AL build`, `:AL downloadSymbols`, `:AL definition`
- **Treesitter** — syntax highlighting via [tree-sitter-al]
- **Snippets** — AL snippets via LuaSnip, plus the snippets bundled with the
  installed AL extension and the design pattern, test, upgrade and FlowField
  snippets of the CRS AL Language extension (`ttestcasewaldo`...), and
  `tappjson` / `tdependency` in app.json (new id, runtime from the application
  version)
- **Code cleanup** — add the missing ToolTips (AA0218) to page fields and
  actions and Captions to table fields, in a file or the whole project
- **File naming** — rename and reorganize files after the object they contain,
  with the same patterns and `CRS.*` settings as the CRS AL Language extension
- **Variables** — variable names from the type (nvim-cmp source and `v*`
  snippets), jump to the local/global var section and sort declarations as
  CodeCop AA0021 expects
- **New object wizards** — `:AL newObject` with the next free id, and list/card
  pages, reports, queries and xmlports generated from a table
- **Progress notifications** — real-time feedback during project loading and
  builds

## Requirements

- Neovim >= 0.10
- [Microsoft AL Language Extension] (provides the language server). Install it
  with `:AL installExtension` (needs `curl` and `unzip`), or reuse the one
  installed by VS Code.
- [.NET 10 runtime](https://dotnet.microsoft.com/download) (`dotnet` on PATH):
  since v18 the extension ships the language server as a cross-platform `.dll`

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "abonckus/al.nvim",
    ft = "al",
    dependencies = {
        "nvim-neotest/nvim-nio",
    },
    opts = {},
}
```

### With debugging support

```lua
{
    "abonckus/al.nvim",
    ft = "al",
    dependencies = {
        "nvim-neotest/nvim-nio",
        "mfussenegger/nvim-dap",
        "rcarriga/nvim-dap-ui",
        "theHamsta/nvim-dap-virtual-text",
    },
    opts = {},
}
```

### With multi-project workspace support

```lua
{
    "abonckus/al.nvim",
    ft = "al",
    dependencies = {
        "nvim-neotest/nvim-nio",
        "abonckus/code-workspace.nvim",
    },
    opts = {},
}
```

## Configuration

All options with their defaults:

```lua
require("al").setup({
    -- Where `:AL installExtension` installs the AL Language extension.
    -- Scanned first for the extension (highest version wins).
    extensionsPath = vim.fn.stdpath("data") .. "/al-extension",

    -- Path to VS Code extensions directory, used as a fallback.
    vscodeExtensionsPath = "~\\.vscode\\extensions\\",

    -- .NET host used to start the language server .dll (extension v18+).
    dotnetPath = "dotnet",

    -- Allow `:AL installExtension` to install Marketplace pre-releases.
    extensionPrerelease = false,

    integrations = {
        luasnip = true,
    },

    lsp = {
        telemetryLevel = "all",       -- "none" | "crash" | "error" | "all"
        browser = "SystemDefault",    -- "SystemDefault" | "Chrome" | "Firefox"
                                      -- | "Edge" | "EdgeBeta"
        inlayHintsParameterNames = true,
        inlayHintsFunctionReturnTypes = true,
        semanticFolding = true,
        extendGoToSymbolInWorkspace = true,
        extendGoToSymbolInWorkspaceResultLimit = 100,
        extendGoToSymbolInWorkspaceIncludeSymbolFiles = true,
        log = {
            path = "",
            level = "Normal",         -- "Debug" | "Verbose" | "Normal"
                                      -- | "Warning" | "Error"
        },
    },

    workspace = {
        alResourceConfigurationSettings = {
            assemblyProbingPaths = { "./.netpackages" },
            codeAnalyzers = {
                "${CodeCop}",
                "${analyzerFolder}BusinessCentral.LinterCop.dll",
            },
            enableCodeAnalysis = true,
            backgroundCodeAnalysis = true,
            packageCachePaths = { "./.alpackages" },
            ruleSetPath = ".vscode/ruleset.json",
            enableCodeActions = true,
            incrementalBuild = false,
            outputAnalyzerStatistics = false,
            enableExternalRulesets = true,
        },
    },

    -- Multi-project workspace settings (used with code-workspace.nvim)
    multiproject = {
        -- Relative path to per-project settings file (read for
        -- alResourceConfigurationSettings overrides per folder)
        settings_path = ".vscode/settings.json",
        -- Maximum time (ms) to wait for a project closure to load
        closure_timeout_ms = 300000,
    },

    -- :AL renameFile / reorganizeFile (see "File naming" below)
    files = {
        pattern = "<ObjectNameShort>.<ObjectTypeShortPascalCase>.al",
        subfolder = "src",
        on_save = "none", -- "none" | "rename" | "reorganize"
        use_git_mv = false,
    },
})
```

## Commands

| Command | Description |
|---|---|
| `:AL config [name]` | Set the active launch configuration for the session |
| `:AL build` | Build the current AL package |
| `:AL publish` | Authenticate, build, and publish to Business Central |
| `:AL downloadSymbols` | Download symbols for a launch configuration |
| `:AL refreshSymbols` | Refresh symbol references (lightweight) |
| `:AL downloadSource` | Download source for a symbol |
| `:AL authenticate` | Authenticate for a launch configuration |
| `:AL clearCredentialsCache` | Clear cached credentials |
| `:AL definition` | Go to AL definition (uses al/gotodefinition) |
| `:AL runObject [Type] [Id]` | Run a Business Central object. `current` runs the object in the buffer; `testTool`, `eventSubscribers` and `databaseLocks` open those system pages |
| `:AL openInBrowser` | Open Business Central web client |
| `:AL restartLsp` | Restart the AL language server |
| `:AL installExtension` | Download the latest AL Language extension from the Marketplace |
| `:AL updateExtension` | Same as `installExtension`; restarts the server if the version changed |
| `:AL eventPublishers` | List event publishers in quickfix |
| `:AL symbolSearch [query]` | Search AL symbols |
| `:AL dependencies` | Show package dependencies |
| `:AL generatePermissionSet` | Generate a permission set AL object |
| `:AL renameFile` | Rename the current file after its object |
| `:AL renameAllFiles` | Rename every AL file of the project (asks first) |
| `:AL reorganizeFile` | Move the current file to `<subfolder>/<object type>/` and rename it |
| `:AL reorganizeAllFiles` | Reorganize every AL file of the project (asks first) |
| `:AL gotoLocalVars` | Jump to the var section of the current procedure (adds one if missing) |
| `:AL gotoGlobalVars` | Jump to the object's global var section |
| `:AL sortVariables` | Sort every var section in the AA0021 order |
| `:AL newObject [type]` | Create an object with the next free id from app.json |
| `:AL createListPage` | List page from the table in the buffer (all its fields) |
| `:AL createCardPage` | Card page from the table in the buffer |
| `:AL createReport` | Report with a column per field of the table in the buffer |
| `:AL createQuery` | Query with a column per field of the table in the buffer |
| `:AL createXmlPort` | XmlPort with an element per field of the table in the buffer |
| `:AL addToolTips [project]` | Add missing ToolTips to page fields and actions (AA0218) |
| `:AL addFieldCaptions [project]` | Add missing Captions to table fields |
| `:AL searchDocs [terms]` | Search Microsoft Learn (default: the word under the cursor) |
| `:AL lsp` | Show AL LSP client info and settings |

## Variables

Variable names are built from the object name, like the AL Variable Helper
extension: the full name, an abbreviated one using the Microsoft abbreviations
and the capitals (`Record "Sales Header"` → `SalesHeader`, `SalesHdr`, `SH`).
Temporary records get the `Temp` prefix that AA0073 requires.

- **Snippets** (LuaSnip): `vrecord`, `vcodeunit`, `vreport`, `vxmlport`,
  `vquery`, `vpage`, `vtestpage`, `venum` and `vinterface`. Type the object
  first; the name follows it. In `vrecord` the second field chooses
  `temporary`.
- **nvim-cmp source** `al_var`: with the cursor on the name of a declaration
  (`|: Record Customer;`), it offers the names above. Add it to your sources:

  ```lua
  sources = cmp.config.sources({ { name = "nvim_lsp" }, { name = "al_var" }, ... })
  ```

- `variables.ignore_prefixes` / `ignore_suffixes` are removed from object names
  first, together with `files.object_name_prefix` / `object_name_suffix`.
- `:AL sortVariables` puts Record, Report, Codeunit, XmlPort, Page, Query,
  Notification, BigText, DateFormula, RecordId, RecordRef, FieldRef and
  FilterPageBuilder first, in that order; other declarations keep their order.
  Sections with `#if` directives are left untouched.

## New objects

`:AL newObject` asks for the type, the name and, depending on the type, the
extended object or the source table. The id is the first one in the app.json
`idRanges` not used by another object of the same type, the file is named with
the [file naming](#file-naming) patterns and the object reuses the namespace
of the current file.

`:AL createListPage`, `createCardPage`, `createReport`, `createQuery` and
`createXmlPort` work on the table in the current buffer and add all its fields
(FlowFilters, removed fields and Blob/Media fields are left out), so you only
delete the ones you do not need. Outside a table they ask for the table name and
create the object without fields. The new file goes to the folder of its type
when the project has one folder per type (`src/table/` → `src/page/`).

```lua
objects = {
    application_area = "All",
    application_area_on_fields = false, -- true: on every field, not on the object
    field_tooltip = "Specifies the value of the %1 field.",
    action_tooltip = "Executes the %1 action.", -- used by :AL addToolTips
    list_usage_category = "Lists",
},
```

`:AL addToolTips` and `:AL addFieldCaptions` use the same texts: page fields get
`field_tooltip` with the source field name, actions get `action_tooltip`, and
table fields get their name as Caption. API pages are skipped. Add `project` to
change every AL file of the project.

## File naming

`:AL renameFile` and `:AL reorganizeFile` work like the CRS AL Language
extension. The default pattern, `<ObjectNameShort>.<ObjectTypeShortPascalCase>.al`,
is the one the AA0215 rule expects (`CustomerList.Page.al`). Patterns can use
`<ObjectType>`, `<ObjectTypeShort>`, `<ObjectTypeShortPascalCase>`,
`<ObjectTypeShortUpper>`, `<ObjectId>`, `<ObjectName>`, `<ObjectNameShort>`,
`<BaseName>`, `<BaseNameShort>`, `<BaseId>`, `<Prefix>` and `<Suffix>`.

- Extension objects use `pattern_extensions`; page customizations use
  `pattern_page_customizations`. `<BaseId>` comes from a comment after the base
  object: `pageextension 50100 "My Ext" extends "Customer Card" // 21`.
- Reorganize moves files to `<root>/<subfolder>/<object type>/`, or to folders
  built from the namespace with `by_namespace = true`. Test codeunits go to
  `<root>/test/`.
- `object_name_prefix` / `object_name_suffix` are added to the object name in
  the file when missing; `remove_prefix_from_filename` /
  `remove_suffix_from_filename` leave them out of the file name.
- `on_save = "rename"` or `"reorganize"` applies it every time an AL file is
  saved.
- The `CRS.*` keys in the project's `.vscode/settings.json` (`CRS.FileNamePattern`,
  `CRS.AlSubFolderName`, `CRS.OnSaveAlFileAction`, `CRS.RenameWithGit`,
  `CRS.ObjectNamePrefix`...) override these options, so projects already set up
  for CRS keep their naming. Set `read_crs_settings = false` to ignore them.

## Statusline

al.nvim exposes a statusline API for displaying AL project state:

```lua
local status = require("al.state").statusline()
-- status.config         -- active launch config name (string|nil)
-- status.lsp            -- AL language server attached (boolean)
-- status.closure_loaded -- project closure loaded (boolean)
-- status.project        -- current project name in multi-project mode (string|nil)
```

Example lualine component:

```lua
{
  function()
    local s = require("al.state").statusline()
    if not s.lsp then return "" end
    local parts = { "AL" }
    if s.project then parts[#parts+1] = s.project end
    if s.config then parts[#parts+1] = s.config end
    if not s.closure_loaded then parts[#parts+1] = "loading..." end
    return table.concat(parts, " | ")
  end,
  cond = function() return vim.bo.filetype == "al" end,
}
```

## Multi-project Workspaces

al.nvim supports multi-project workspaces through integration with
[code-workspace.nvim]. When you open a `.code-workspace` file, al.nvim:

1. Starts a single AL Language Server instance for all projects
2. Sends `al/loadManifest` for each project folder
3. Computes project-reference closures from `app.json` dependencies
4. Switches the active workspace on `BufEnter` (100ms debounce)
5. Sends `workspace/didChangeConfiguration` for dependency folders
6. Shows server progress notifications during closure loading

### How it works

Each workspace folder with an `app.json` is treated as an AL project. When you
open a file in a project, al.nvim computes which other workspace projects are
dependencies (by matching `app.json` dependency IDs) and sends the full closure
to the server via `al/setActiveWorkspace`.

The server's `rootPath` is set to the first AL project folder in the workspace
(alphabetically), matching VS Code's behavior.

### Per-project settings

Each project can override workspace-level `alResourceConfigurationSettings` by
placing them in a settings file (default `.vscode/settings.json`) under the key
`al.alResourceConfigurationSettings`. Global defaults are merged with
per-project settings, with per-project values taking precedence.

### Example workspace

```
my-workspace/
├── my-workspace.code-workspace
├── Cloud/
│   ├── app.json
│   ├── .vscode/settings.json
│   └── src/
├── Test/
│   ├── app.json          (depends on Cloud)
│   ├── .vscode/settings.json
│   └── src/
└── DemoApp/
    ├── app.json          (depends on Cloud)
    └── src/
```

Opening a file in `Test/` sends a closure of `[Test, Cloud]` to the server.
Opening a file in `Cloud/` sends a closure of `[Cloud]` only.

## Debugging

al.nvim routes DAP traffic through a Go proxy binary to solve stdio handle
crashes in AL EditorServices. The proxy is bundled in `bin/` for all platforms:

| Platform       | Binary                       |
|----------------|------------------------------|
| Windows        | `al-debug-proxy.exe`         |
| Linux          | `al-debug-proxy`             |
| macOS (Intel)  | `al-debug-proxy-darwin`      |
| macOS (ARM)    | `al-debug-proxy-darwin-arm64`|

Debug configurations are read from `.vscode/launch.json`. Set `"type": "al"` in
your launch configuration.

```vim
:DapToggleBreakpoint    " Set breakpoints
:DapContinue            " Start debugging
```

For technical details on the proxy, see [DEBUGGING.md](DEBUGGING.md).

### Building the proxy from source

Requires Go 1.21+:

```bash
cd proxy-src && ./build.sh     # Unix
cd proxy-src && build.bat      # Windows
```

## Project structure

```
your-al-project/
├── app.json              AL app manifest
├── .alpackages/          Symbol packages
├── .vscode/
│   ├── launch.json       Debug configurations
│   ├── settings.json     Per-project settings (multi-project)
│   └── ruleset.json      Code analysis rules
└── src/
    └── *.al
```

## Dependencies

| Plugin | Purpose | Required |
|--------|---------|----------|
| [nvim-nio] | Async I/O for multi-project and debugging | Yes |
| [code-workspace.nvim] | Multi-project workspace detection | For multi-project |
| [nvim-dap] | Debug Adapter Protocol | For debugging |
| [nvim-dap-ui] | Debug UI | For debugging |
| [nvim-dap-virtual-text] | Inline debug values | For debugging |
| [nvim-treesitter] + [tree-sitter-al] | Syntax highlighting | Optional |
| [LuaSnip] | AL snippets | Optional |
| [lsp-output.nvim] | LSP server log viewer | Optional |

## License

See [LICENSE](LICENSE).

<!-- link references -->
[Microsoft AL Language Extension]: https://marketplace.visualstudio.com/items?itemName=ms-dynamics-smb.al
[code-workspace.nvim]: https://github.com/abonckus/code-workspace.nvim
[nvim-nio]: https://github.com/nvim-neotest/nvim-nio
[nvim-dap]: https://github.com/mfussenegger/nvim-dap
[nvim-dap-ui]: https://github.com/rcarriga/nvim-dap-ui
[nvim-dap-virtual-text]: https://github.com/theHamsta/nvim-dap-virtual-text
[nvim-treesitter]: https://github.com/nvim-treesitter/nvim-treesitter
[tree-sitter-al]: https://github.com/SShadowS/tree-sitter-al
[LuaSnip]: https://github.com/L3MON4D3/LuaSnip
[lsp-output.nvim]: https://github.com/abonckus/lsp-output.nvim
