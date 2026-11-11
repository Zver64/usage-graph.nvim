local graph = require("usage-graph.graph")
local lsp = require("usage-graph.lsp")
local render = require("usage-graph.render")

local M = {}

M.config = {
  -- How many levels of users to follow; nil = until there are none left.
  max_depth = nil,
  -- Stop adding symbols after this many (the graph is then marked truncated).
  max_nodes = 500,
  -- Per LSP request.
  timeout_ms = 15000,
}

function M.setup(opts)
  M.config = vim.tbl_extend("force", M.config, opts or {})
end

--- Builds the usage graph of the symbol under the cursor.
---@param callback fun(err: string?, graph: table?)
function M.build(callback)
  local bufnr = vim.api.nvim_get_current_buf()
  local client = lsp.pick_client(bufnr)
  if not client then
    return callback("no LSP client supporting references and documentSymbol is attached to this buffer")
  end
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  local cword = vim.fn.expand("<cword>")
  lsp.run(function()
    local source = lsp.source(client, M.config)
    local root = lsp.resolve_root(source, params.textDocument.uri, params.position, cword)
    return graph.build(source, root, M.config)
  end, callback)
end

--- Builds the graph for the symbol under the cursor and opens it in the browser.
function M.show()
  local function fail(err)
    vim.notify("usage-graph: " .. err, vim.log.levels.ERROR)
  end
  M.build(function(err, g)
    if err then
      return fail(err)
    end
    local name = g.nodes[g.order[1]].name
    if #g.edges == 0 then
      return vim.notify(("usage-graph: nothing uses `%s`"):format(name))
    end
    render.write(g, function(render_err, path)
      if render_err then
        return fail(render_err)
      end
      render.open(path)
      local msg = ("usage-graph: `%s`: %d symbols, %d edges"):format(name, #g.order, #g.edges)
      if g.truncated then
        msg = msg .. (" (truncated at max_nodes = %d)"):format(M.config.max_nodes)
      end
      vim.notify(msg, g.truncated and vim.log.levels.WARN or vim.log.levels.INFO)
    end)
  end)
end

return M
