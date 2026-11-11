-- Graph -> Graphviz DOT. Symbols are grouped into one cluster per file;
-- an edge goes from a symbol to the symbol that uses it.

local M = {}

local function quote(s)
  return '"' .. (s:gsub("\\", "\\\\"):gsub('"', '\\"')) .. '"'
end

local function relpath(uri)
  return vim.fn.fnamemodify(vim.uri_to_fname(uri), ":.")
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
  for i, uri in ipairs(files) do
    local path = relpath(uri)
    out[#out + 1] = ("  subgraph cluster_%d {"):format(i)
    out[#out + 1] = ("    label=%s;"):format(quote(path))
    out[#out + 1] = '    style="rounded"; color="#bbbbbb";'
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
