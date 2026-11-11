-- The LSP side: a coroutine runner and a graph `source` backed by one client.

local symbols = require("usage-graph.symbols")

local M = {}

--- Runs `fn` in a coroutine. Inside it, async steps yield a `function(resume)`.
---@param fn fun(): any
---@param callback fun(err: string?, result: any)
function M.run(fn, callback)
  local co = coroutine.create(fn)
  local function step(...)
    local ok, value = coroutine.resume(co, ...)
    if not ok then
      return callback(tostring(value))
    end
    if coroutine.status(co) == "dead" then
      return callback(nil, value)
    end
    value(step)
  end
  step()
end

local function request(client, method, params, bufnr, timeout_ms)
  local err, result = coroutine.yield(function(resume)
    local settled = false
    local function settle(e, r)
      if settled then
        return
      end
      settled = true
      vim.schedule(function()
        resume(e, r)
      end)
    end
    if not client:request(method, params, settle, bufnr) then
      settle("the LSP client has shut down")
    end
    vim.defer_fn(function()
      settle("timed out")
    end, timeout_ms)
  end)
  if err then
    error(("%s: %s"):format(method, type(err) == "table" and err.message or tostring(err)), 0)
  end
  return result
end

--- The first client of the buffer that can answer both requests the graph needs.
function M.pick_client(bufnr)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    if
      client:supports_method("textDocument/references", bufnr)
      and client:supports_method("textDocument/documentSymbol", bufnr)
    then
      return client
    end
  end
end

---@param client vim.lsp.Client
---@param opts { timeout_ms: integer }
function M.source(client, opts)
  local cache = {}

  -- Servers answer documentSymbol only for documents they were told are open.
  local function open(uri)
    local bufnr = vim.uri_to_bufnr(uri)
    if not vim.api.nvim_buf_is_loaded(bufnr) then
      vim.fn.bufload(bufnr)
    end
    if not vim.lsp.buf_is_attached(bufnr, client.id) then
      vim.lsp.buf_attach_client(bufnr, client.id)
    end
    return bufnr
  end

  local source = {}

  function source.references(uri, pos)
    local bufnr = open(uri)
    return request(client, "textDocument/references", {
      textDocument = { uri = uri },
      position = pos,
      context = { includeDeclaration = false },
    }, bufnr, opts.timeout_ms) or {}
  end

  function source.symbols(uri)
    if not cache[uri] then
      local bufnr = open(uri)
      local result =
        request(client, "textDocument/documentSymbol", { textDocument = { uri = uri } }, bufnr, opts.timeout_ms)
      cache[uri] = symbols.normalize(result, {
        encoding = client.offset_encoding,
        get_line = function(lnum)
          return vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
        end,
      })
    end
    return cache[uri]
  end

  --- Where the symbol at `pos` is declared: { uri, pos } or nil.
  function source.definition(uri, pos)
    local bufnr = open(uri)
    if not client:supports_method("textDocument/definition", bufnr) then
      return nil
    end
    local result = request(
      client,
      "textDocument/definition",
      { textDocument = { uri = uri }, position = pos },
      bufnr,
      opts.timeout_ms
    )
    local loc = result and (result.uri and result or result[1])
    if not loc then
      return nil
    end
    return {
      uri = loc.uri or loc.targetUri,
      pos = (loc.range or loc.targetSelectionRange).start,
    }
  end

  return source
end

--- Turns a cursor position into the graph root: the declaration of what is
--- under the cursor, so that a cycle leading back to it is recognised.
function M.resolve_root(source, uri, pos, fallback_name)
  local function declared_at(u, p)
    local sym = symbols.at_selection(source.symbols(u), p)
    if sym then
      return { uri = u, pos = sym.selection.start, name = sym.path, kind = sym.kind }
    end
  end

  local root = declared_at(uri, pos)
  if root then
    return root
  end
  local def = source.definition(uri, pos)
  if def then
    -- Not a document symbol (e.g. a local variable): still a valid root.
    return declared_at(def.uri, def.pos) or { uri = def.uri, pos = def.pos, name = fallback_name }
  end
  return { uri = uri, pos = pos, name = fallback_name }
end

return M
