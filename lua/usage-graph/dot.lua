-- Graph -> Graphviz DOT. Symbols are grouped into one cluster per file;
-- an edge goes from a symbol to the symbol that uses it.

local M = {}

local function quote(s)
  return '"' .. (s:gsub("\\", "\\\\"):gsub('"', '\\"')) .. '"'
end

-- Graphviz has no padding for a cluster label, and it measures text a few percent
-- narrower than browsers draw it, so a label wider than the nodes inside touches
-- the border. Non-breaking spaces on both sides keep the label centred and clear.
local function padded(s)
  local pad = ("\194\160"):rep(4)
  return quote(pad .. s .. pad)
end

local function relpath(uri)
  return vim.fn.fnamemodify(vim.uri_to_fname(uri), ":.")
end

-- For every path, the shortest tail that no other path of the graph ends with:
-- "model.ts", or "user/index.ts" when there are several "index.ts".
local function short_names(paths)
  local parts = {}
  for _, path in ipairs(paths) do
    parts[path] = vim.split(path, "/", { plain = true })
  end
  local function tail(path, n)
    local p = parts[path]
    return table.concat(p, "/", math.max(#p - n + 1, 1))
  end
  local names = {}
  for _, path in ipairs(paths) do
    local n = 1
    while n < #parts[path] do
      local unique = true
      for _, other in ipairs(paths) do
        if other ~= path and tail(other, n) == tail(path, n) then
          unique = false
          break
        end
      end
      if unique then
        break
      end
      n = n + 1
    end
    names[path] = tail(path, n)
  end
  return names
end

---@param graph table result of graph.build()
---@return string
function M.generate(graph)
  local ids, files, by_file = {}, {}, {}
  for i, key in ipairs(graph.order) do
    local node = graph.nodes[key]
    ids[key] = "n" .. i
    if not by_file[node.uri] then
      by_file[node.uri] = {}
      files[#files + 1] = node.uri
    end
    table.insert(by_file[node.uri], node)
  end

  local out = {
    "digraph usage {",
    "  rankdir=LR;",
    '  fontname="Helvetica";',
    '  node [shape=box, style="rounded,filled", fillcolor="#f2f2f2", color="#888888", fontname="Helvetica"];',
    '  edge [color="#666666"];',
  }
  local paths = vim.tbl_map(relpath, files)
  local names = short_names(paths)
  for i, path in ipairs(paths) do
    local uri = files[i]
    out[#out + 1] = ("  subgraph cluster_%d {"):format(i)
    -- The full path is on hover; filled, so that the whole box reacts to it.
    out[#out + 1] = ("    label=%s; tooltip=%s;"):format(padded(names[path]), quote(path))
    out[#out + 1] = '    style="rounded,filled"; fillcolor="#ffffff"; color="#bbbbbb";'
    for _, node in ipairs(by_file[uri]) do
      local attrs = {}
      if node.file then
        attrs[#attrs + 1] = "label=" .. quote("(file scope)")
        attrs[#attrs + 1] = 'style="rounded,dashed"'
        attrs[#attrs + 1] = "tooltip=" .. quote(path)
      else
        local kind = vim.lsp.protocol.SymbolKind[node.kind]
        local where = ("%s:%d"):format(path, node.pos.line + 1)
        attrs[#attrs + 1] = "label=" .. quote(node.name)
        attrs[#attrs + 1] = "tooltip=" .. quote(kind and (kind .. " · " .. where) or where)
      end
      if node.root then
        attrs[#attrs + 1] = 'fillcolor="#ffd866"'
        attrs[#attrs + 1] = "penwidth=2"
      end
      out[#out + 1] = ("    %s [%s];"):format(ids[node.key], table.concat(attrs, ", "))
    end
    out[#out + 1] = "  }"
  end
  for _, edge in ipairs(graph.edges) do
    out[#out + 1] = ("  %s -> %s;"):format(ids[edge.from], ids[edge.to])
  end
  out[#out + 1] = "}"
  return table.concat(out, "\n") .. "\n"
end

return M
