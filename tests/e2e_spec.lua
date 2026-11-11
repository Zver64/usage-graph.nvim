-- The whole path against an in-process language server:
-- cursor -> LSP requests -> graph -> dot -> HTML page.

local function eq(expected, actual)
  assert(vim.deep_equal(expected, actual), ("expected %s, got %s"):format(vim.inspect(expected), vim.inspect(actual)))
end

local function range(l1, c1, l2, c2)
  return { start = { line = l1, character = c1 }, ["end"] = { line = l2, character = c2 } }
end

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local function write(name, lines)
  vim.fn.writefile(lines, dir .. "/" .. name)
  return vim.uri_from_fname(vim.uv.fs_realpath(dir .. "/" .. name))
end

local model = write("model.lua", { "local User = {}", "return User" })
local service = write("service.lua", {
  'local User = require("model")',
  "local function load()",
  "  return User",
  "end",
  "load()",
})

-- What the fake server knows about the two files.
local symbols = {
  [model] = { { name = "User", kind = 13, range = range(0, 0, 0, 15), selectionRange = range(0, 6, 0, 10) } },
  [service] = { { name = "load", kind = 12, range = range(1, 0, 3, 3), selectionRange = range(1, 15, 1, 19) } },
}
local references = {
  [model .. "#0:6"] = {
    { uri = service, range = range(0, 6, 0, 10) },
    { uri = service, range = range(2, 9, 2, 13) },
  },
  [service .. "#1:15"] = { { uri = service, range = range(4, 0, 4, 4) } },
}

local log = {}
local function server(dispatchers)
  local closing = false
  return {
    request = function(method, params, callback)
      log[#log + 1] = method .. " " .. vim.fs.basename((params.textDocument or {}).uri or "")
      if method == "initialize" then
        callback(nil, {
          capabilities = {
            referencesProvider = true,
            documentSymbolProvider = true,
            definitionProvider = true,
            textDocumentSync = { openClose = true, change = 1 },
          },
        })
      elseif method == "textDocument/documentSymbol" then
        callback(nil, symbols[params.textDocument.uri])
      elseif method == "textDocument/references" then
        local pos = params.position
        callback(nil, references[("%s#%d:%d"):format(params.textDocument.uri, pos.line, pos.character)])
      elseif method == "textDocument/definition" then
        -- Every `User` in service.lua resolves to its declaration in model.lua.
        callback(nil, { uri = model, range = range(0, 6, 0, 10) })
      else
        callback(nil, nil)
      end
      return true, #log
    end,
    notify = function(method, params)
      log[#log + 1] = method .. " " .. vim.fs.basename(((params or {}).textDocument or {}).uri or "")
      if method == "exit" then
        closing = true
        dispatchers.on_exit(0, 0)
      end
      return true
    end,
    is_closing = function()
      return closing
    end,
    terminate = function()
      closing = true
    end,
  }
end

local function await(start)
  local done, err, result = false, nil, nil
  start(function(e, r)
    done, err, result = true, e, r
  end)
  assert(
    vim.wait(5000, function()
      return done
    end),
    "timed out"
  )
  assert(not err, err)
  return result
end

--- Opens service.lua with the fake server attached, cursor on `User` in `return User`.
local function open_service()
  vim.cmd.edit(vim.uri_to_fname(service))
  local id = assert(vim.lsp.start({ name = "fake", cmd = server, root_dir = dir }))
  assert(
    vim.wait(5000, function()
      return vim.lsp.get_client_by_id(id).initialized
    end),
    "the fake server did not initialize"
  )
  vim.api.nvim_win_set_cursor(0, { 3, 10 })
end

local function describe(g)
  local nodes = vim.tbl_map(function(key)
    local node = g.nodes[key]
    return (node.file and "<file>" or node.name) .. " @ " .. vim.fs.basename(node.uri)
  end, g.order)
  local edges = vim.tbl_map(function(edge)
    local to = g.nodes[edge.to]
    return g.nodes[edge.from].name .. " -> " .. (to.file and "<file>" or to.name)
  end, g.edges)
  return nodes, edges
end

return {
  ["builds the graph from a usage under the cursor"] = function()
    open_service()
    local g = await(require("usage-graph").build)
    local nodes, edges = describe(g)
    -- The root is the declaration, not the usage the cursor was on.
    eq({ "User @ model.lua", "<file> @ service.lua", "load @ service.lua" }, nodes)
    eq({ "User -> <file>", "User -> load", "load -> <file>" }, edges)
  end,

  ["files the user never opened are opened on the server before being queried"] = function()
    local opened, asked
    for i, entry in ipairs(log) do
      opened = opened or (entry == "textDocument/didOpen model.lua" and i)
      asked = asked or (entry == "textDocument/documentSymbol model.lua" and i)
    end
    assert(opened and asked and opened < asked, vim.inspect(log))
  end,

  ["renders the graph into an HTML page with an SVG"] = function()
    open_service()
    local ug = require("usage-graph")
    local g = await(ug.build)
    local path = await(function(cb)
      require("usage-graph.render").write(g, cb)
    end)
    local html = table.concat(vim.fn.readfile(path), "\n")
    assert(html:find("<svg", 1, true), "no <svg> in the page")
    assert(not html:find("<?xml", 1, true), "the XML prolog must be stripped")
    for _, text in ipairs({ ">User<", ">load<", ">(file scope)<", "model.lua", "service.lua" }) do
      assert(html:find(text, 1, true), "missing in the page: " .. text)
    end
  end,

  ["every graph is a new file in Neovim's temp directory"] = function()
    open_service()
    local g = await(require("usage-graph").build)
    local function render(cb)
      require("usage-graph.render").write(g, cb)
    end
    local first, second = await(render), await(render)
    assert(first ~= second, "the second graph overwrote the first: " .. first)
    local tmp = vim.fs.dirname(vim.fn.tempname())
    assert(vim.startswith(first, tmp) and vim.startswith(second, tmp), first .. " is outside " .. tmp)
  end,

  ["reports a buffer without a suitable LSP client"] = function()
    vim.cmd.enew()
    local done, err = false, nil
    require("usage-graph").build(function(e)
      done, err = true, e
    end)
    assert(done and err:find("no LSP client", 1, true), tostring(err))
  end,
}
