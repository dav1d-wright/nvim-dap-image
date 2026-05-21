# nvim-dap-image

View image variables during debug sessions in Neovim. Place your cursor on an OpenCV `cv::Mat`, PIL Image, NumPy array, or Matplotlib figure, press a key, and see it rendered in a floating window.

Works with codelldb and cppdbg (C++) and debugpy (Python).

![Python demo](https://gitlab.com/david_wright/nvim-dap-image/-/raw/assets/assets/python_demo.mov)

## Requirements

- [nvim-dap](https://github.com/mfussenegger/nvim-dap) - Debug Adapter Protocol client
- [image.nvim](https://github.com/3rd/image.nvim) - Terminal image rendering (Kitty graphics protocol, sixel, or ueberzug)
- A terminal that supports image display (Kitty, Ghostty, WezTerm, etc.)

### Debug Adapter Dependencies

The plugin works by evaluating expressions in the debuggee process to write images to temporary PNG files. This means the debuggee must have the relevant imaging library available.

**C++ (codelldb or cppdbg):**

- OpenCV must be linked into the debuggee binary
- The debug adapter must support expression evaluation with function calls
- **codelldb** (LLDB-based): Tested. Supports expression evaluation and `readMemory` for future fallback support.
- **cppdbg** (GDB/LLDB via vscode-cpptools): Should work via GDB's expression evaluation. Function calls in the debuggee require debug symbols.

**Python (debugpy):**

- For OpenCV images: `cv2` (opencv-python) must be importable
- For PIL images: `Pillow` must be importable
- For NumPy arrays: `numpy` and `Pillow` must be importable (converts via `PIL.Image.fromarray`)
- For Matplotlib figures: `matplotlib` must be importable

## Installation

### lazy.nvim

```lua
{
  url = "https://gitlab.com/david_wright/nvim-dap-image",
  -- GitHub mirror: "dav1d-wright/nvim-dap-image"
  dependencies = { "mfussenegger/nvim-dap", "3rd/image.nvim" },
  config = function()
    require("nvim-dap-image").setup()
  end,
}
```

## Usage

1. Start a debug session and hit a breakpoint
2. Place cursor on an image variable name
3. Run `:DapImageView` (or press `<leader>di` if mapped)
4. A floating window renders the image
5. Press `q` or `<Esc>` to close the viewer

### Commands

| Command                | Description                                            |
| ---------------------- | ------------------------------------------------------ |
| `:DapImageView [expr]` | View variable as image. Defaults to word under cursor. |
| `:DapImageClose`       | Close the currently focused image viewer               |
| `:DapImageCloseAll`    | Close all open image viewers                           |

### Suggested keybinding

```lua
vim.keymap.set("n", "<leader>di", "<cmd>DapImageView<cr>", { desc = "View variable as image" })
```

## Configuration

```lua
require("nvim-dap-image").setup({
  -- Directory for temporary image files (defaults to system temp dir)
  tmp_dir = vim.uv.os_tmpdir() .. "/nvim-dap-image",

  -- Floating window settings
  window = {
    width_pct = 0.6,    -- percentage of editor width
    height_pct = 0.6,   -- percentage of editor height
    border = "rounded", -- border style
  },

  -- Close all image viewers when the debug session ends
  auto_close_on_terminate = true,

  -- Delete temp files when a viewer is closed
  auto_cleanup_temp = true,

  -- Additional user-defined extractors (see Custom Extractors below)
  extractors = {},
})
```

## Custom Extractors

You can add extractors for new image types or filetypes:

```lua
require("nvim-dap-image").setup({
  extractors = {
    {
      name = "PyTorch Tensor",
      filetypes = "python",  -- string or list of strings
      priority = 5, -- lower = tried first
      detect = function(var_name)
        return "hasattr(" .. var_name .. ", 'is_cuda')"
      end,
      extract = function(var_name, tmp_path, helpers, callback)
        helpers.evaluate(
          "__import__('torchvision.utils', fromlist=['save_image']).save_image("
            .. var_name .. ", '" .. tmp_path .. "')",
          callback
        )
      end,
    },
  },
})
```

Or register at runtime:

```lua
require("nvim-dap-image").register_extractor({
  name = "My Custom Type",
  filetypes = { "python" },
  priority = 15,
  detect = function(var_name) return "isinstance(" .. var_name .. ", MyImageType)" end,
  extract = function(var_name, tmp_path, helpers, callback)
    helpers.evaluate(var_name .. ".save('" .. tmp_path .. "')", callback)
  end,
})
```

### Extractor interface

| Field       | Type                                                                                   | Description                                                                                                                                                                     |
| ----------- | -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `name`      | `string`                                                                               | Human-readable name shown in the viewer title                                                                                                                                   |
| `filetypes` | `string\|string[]`                                                                     | Neovim filetype(s) this extractor applies to (e.g., `"python"`, `{"cpp", "c"}`)                                                                                                 |
| `priority`  | `number`                                                                               | Lower values are tried first                                                                                                                                                    |
| `detect`    | `fun(var_name: string): string`                                                        | Returns a DAP evaluate expression. If it evaluates without error and returns a truthy value, this extractor matches.                                                            |
| `extract`   | `fun(var_name: string, tmp_path: string, helpers: table, callback: fun(err?: string))` | Writes the image to `tmp_path` and calls `callback(nil)` on success or `callback(err)` on failure. Use `helpers.evaluate(expr, callback)` to run an expression in the debuggee. |

## Built-in Extractors

### C/C++ (filetypes: `cpp`, `c`)

| Priority | Name           | Detection            | Extraction                                            |
| -------- | -------------- | -------------------- | ----------------------------------------------------- |
| 10       | OpenCV cv::Mat | Evaluates `var.rows` | Reads pixels via `readMemory`, writes BMP client-side |

### Python (filetype: `python`)

| Priority | Name              | Detection                                   | Extraction                            |
| -------- | ----------------- | ------------------------------------------- | ------------------------------------- |
| 10       | OpenCV image      | `hasattr(var, 'shape')` + `cv2` importable  | `cv2.imwrite(path, var)`              |
| 20       | PIL Image         | `isinstance(var, PIL.Image.Image)`          | `var.save(path, 'PNG')`               |
| 30       | NumPy array       | `isinstance(var, np.ndarray)` + 2D/3D       | `PIL.Image.fromarray(var).save(path)` |
| 40       | Matplotlib Figure | `isinstance(var, matplotlib.figure.Figure)` | `var.savefig(path)`                   |

## How It Works

### Filetype-based extractor dispatch

Extractors are matched to the current buffer's `filetype`, not to the debug adapter type. This means a single adapter like codelldb (which supports C++, Rust, and Zig) automatically uses the correct extractors based on what file you're debugging, with no configuration mapping needed.

When you invoke `:DapImageView`, the plugin reads `vim.bo.filetype` from the current buffer, finds all extractors registered for that filetype, and tries them in priority order.

### Image extraction approach

Extraction works differently for Python and C++ because of a fundamental constraint: in C++ you cannot rely on `cv::imwrite` being linked into the debuggee binary. Most executables don't link OpenCV's `imgcodecs` module.

**Python:** The plugin evaluates an expression in the debuggee via the DAP `evaluate` request. The expression calls image saving functions directly (e.g., `cv2.imwrite(path, var)`, `var.save(path, 'PNG')`) to write the image to a temp file. Only a short file path string crosses the DAP boundary.

**C++:** The plugin reads `cv::Mat` metadata (rows, cols, flags, step) via DAP evaluate, then uses the DAP `readMemory` request to transfer the raw pixel bytes to Neovim. Neovim writes the BMP file client-side. This avoids the dependency on functions in the debuggee.

**Tradeoff:** Both approaches require the debuggee and Neovim to share a filesystem (no remote debugging support).

### Prior art and related projects

These projects solve similar problems in other editors and informed the design:

- **[View Image for Python Debugging](https://github.com/elazarcoh/simply-view-image-for-python-debugging)** (VS Code) - Uses DAP evaluate to call `cv2.imwrite()` in the debuggee, reads temp file back for webview display. Written in Rust + TypeScript. The tempfile approach used here mirrors this strategy.

- **[Debug Visualizer](https://github.com/hediet/vscode-debug-visualizer)** (VS Code, hediet) - General-purpose debug data visualizer. Injects data extractors into the debuggee, uses JSON for structured data exchange. More complex architecture than needed for images alone.

- **[OpenImageDebugger](https://github.com/OpenImageDebugger/OpenImageDebugger)** (GDB/LLDB) - Reads raw pixel memory via GDB/LLDB Python APIs (`val["data"]`, `ReadMemory`). Custom type parser interface. The C++ extraction approach in this plugin is inspired by this strategy.

- **[CodeLLDB Data Visualization](https://github.com/vadimcn/codelldb/wiki/Data-visualization)** - Uses LLDB's `process.ReadMemory()` + Python encoding + HTML data URIs. Purely memory-based, no disk I/O. Efficient but tightly coupled to the CodeLLDB adapter.

- **CLion OpenCV Image Viewer** (JetBrains, built-in since 2024.3) - Native debugger integration, hooks into the Variables panel. Proprietary implementation.

## Development

### Running tests

```bash
make test
```

Requires `plenary.nvim`, `nvim-dap`, and `image.nvim` to be installed (standard lazy.nvim paths).

## License

MIT
