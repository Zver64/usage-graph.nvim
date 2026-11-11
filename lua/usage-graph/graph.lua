-- Builds the graph of everything that (transitively) uses a symbol.
--
-- `source` is the only thing that knows about LSP:
--   source.references(uri, pos) -> { { uri, range }, ... }
--   source.symbols(uri)         -> list from symbols.normalize()
--
-- Result:
--   nodes: key -> { key, uri, pos?, name?, kind?, depth, root?, file? }
--   order: keys in discovery (BFS) order
--   edges: { from = <used>, to = <user> }

local symbols = require("usage-graph.symbols")

local M = {}

function M.key_of(uri, pos)
  return ("%s#%d:%d"):format(uri, pos.line, pos.character)
end

---@param source table
---@param root { uri: string, pos: table, name: string, kind?: integer }
---@param opts? { max_depth?: integer, max_nodes?: integer }
function M.build(source, root, opts)
  opts = opts or {}
  local max_depth = opts.max_depth or math.huge
  local max_nodes = opts.max_nodes or math.huge

  local graph = { nodes = {}, order = {}, edges = {}, truncated = false }
  local seen_edges = {}

  local function add_node(node)
    graph.nodes[node.key] = node
    graph.order[#graph.order + 1] = node.key
    return node
  end

  local queue = {
    add_node({
      key = M.key_of(root.uri, root.pos),
      uri = root.uri,
      pos = root.pos,
      name = root.name,
      kind = root.kind,
      depth = 0,
      root = true,
    }),
  }
  local head = 1

  while queue[head] do
    local node = queue[head]
    head = head + 1
    -- File-scope nodes have no position: nothing to ask references for.
    if node.pos and node.depth < max_depth then
      for _, ref in ipairs(source.references(node.uri, node.pos)) do
        local sym = symbols.enclosing(source.symbols(ref.uri), ref.range.start)
        local key = sym and M.key_of(ref.uri, sym.selection.start) or ref.uri
        -- A symbol referencing itself (recursion, or the declaration itself).
        if key ~= node.key then
          local user = graph.nodes[key]
          if not user then
            if #graph.order >= max_nodes then
              graph.truncated = true
            else
              user = add_node({
                key = key,
                uri = ref.uri,
                pos = sym and sym.selection.start,
                name = sym and sym.path,
                kind = sym and sym.kind,
                depth = node.depth + 1,
                file = not sym,
              })
              queue[#queue + 1] = user
            end
          end
          local edge_key = node.key .. "\n" .. key
          if user and not seen_edges[edge_key] then
            seen_edges[edge_key] = true
            graph.edges[#graph.edges + 1] = { from = node.key, to = key }
          end
        end
      end
    end
  end

  return graph
end

return M
