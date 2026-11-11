# usage-graph.nvim

Shows everything that depends on the symbol under the cursor: what uses it, what
uses those users, and so on until nothing is left. The result is a graph rendered
by Graphviz and opened in the browser.

It is the reverse of a dependency graph: not "what does X depend on" but "what is
affected if X changes". It works with any language that has an LSP server
configured in Neovim.

## Requirements

- Neovim 0.11+
- An LSP server attached to the buffer that supports `textDocument/references`
  and `textDocument/documentSymbol`
- [Graphviz](https://graphviz.org) (`dot` in `PATH`)

## Installation

With the built-in `vim.pack` (Neovim 0.12+):

```lua
vim.pack.add({ "https://github.com/Zver64/usage-graph.nvim" })
```

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ "Zver64/usage-graph.nvim", cmd = "UsageGraph" }
```

No `setup()` call is needed.

## Usage

Put the cursor on a type, function, variable or any other symbol and run:

```vim
:UsageGraph
```

or map it:

```lua
vim.keymap.set("n", "<leader>ug", "<cmd>UsageGraph<cr>", { desc = "Usage graph" })
```

The symbol under the cursor is highlighted. An arrow `A -> B` means "B uses A".
Symbols are grouped by file; hover a node to see its kind and location.

## Configuration

`setup()` is optional; these are the defaults:

```lua
require("usage-graph").setup({
  max_depth = nil,    -- levels of users to follow; nil = to the end
  max_nodes = 500,    -- stop adding symbols after this many
  timeout_ms = 15000, -- per LSP request
})
```

## How it works

1. `textDocument/references` on a symbol gives the places it is used in.
2. `textDocument/documentSymbol` of each of those files tells which symbol a
   place belongs to. That symbol is a user.
3. The same is repeated for every user. Symbols already seen are not visited
   again, so cycles are fine.

What counts as a user:

- Inside a class, interface, struct, enum, module or namespace it is the member
  the reference is in (a method, a field), not the whole container.
- Everything declared inside a function or a variable is its implementation
  detail: a reference in a local variable of `run()` is a use by `run()`.
- A reference outside every symbol (an import, top-level code) is shown as
  `(file scope)` of that file.

The quality of the graph is the quality of the server's answers. Files that
contain usages are loaded into (unlisted) buffers, because servers only describe
documents that are open.

## Tests

```sh
nvim --clean -l tests/run.lua
```
