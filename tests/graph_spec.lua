local graph = require("usage-graph.graph")

local function eq(expected, actual)
  assert(vim.deep_equal(expected, actual), ("expected %s, got %s"):format(vim.inspect(expected), vim.inspect(actual)))
end

-- A fake project: every symbol occupies one line of its file, its name starts at
-- column 0. `uses` lists who references a symbol: "file:Name", or "file" alone
-- for a reference at file scope (outside every symbol).
local function project(decls, uses)
  local files, where = {}, {}
  for _, decl in ipairs(decls) do
    local file, name = decl:match("^(.-):(.+)$")
    files[file] = files[file] or {}
    local line = #files[file]
    table.insert(files[file], {
      name = name,
      path = name,
      kind = 12,
      range = { start = { line = line, character = 0 }, ["end"] = { line = line, character = 50 } },
      selection = { start = { line = line, character = 0 }, ["end"] = { line = line, character = #name } },
    })
    where[decl] = { uri = "file:///" .. file, pos = { line = line, character = 0 } }
  end

  local source = { calls = 0 }
  function source.symbols(uri)
    return files[uri:sub(9)] or {}
  end
  function source.references(uri, pos)
    source.calls = source.calls + 1
    local refs = {}
    for used, users in pairs(uses) do
      if where[used].uri == uri and where[used].pos.line == pos.line then
        for _, user in ipairs(users) do
          local at = where[user]
          local ref_pos = at and { line = at.pos.line, character = 20 } or { line = 999, character = 0 }
          refs[#refs + 1] = {
            uri = at and at.uri or ("file:///" .. user),
            range = { start = ref_pos, ["end"] = ref_pos },
          }
        end
      end
    end
    return refs
  end

  local function root(decl)
    return { uri = where[decl].uri, pos = where[decl].pos, name = decl:match(":(.+)$") }
  end
  return source, root
end

local function names(g)
  return vim.tbl_map(function(key)
    local node = g.nodes[key]
    return node.file and ("<" .. node.uri:sub(9) .. ">") or node.name
  end, g.order)
end

local function edges(g)
  local out = vim.tbl_map(function(edge)
    local from, to = g.nodes[edge.from], g.nodes[edge.to]
    return from.name .. " -> " .. (to.file and ("<" .. to.uri:sub(9) .. ">") or to.name)
  end, g.edges)
  table.sort(out)
  return out
end

return {
  ["follows users of users to the end"] = function()
    local source, root = project(
      { "a.ts:User", "b.ts:loadUser", "c.ts:Profile", "d.ts:App" },
      { ["a.ts:User"] = { "b.ts:loadUser" }, ["b.ts:loadUser"] = { "c.ts:Profile" }, ["c.ts:Profile"] = { "d.ts:App" } }
    )
    local g = graph.build(source, root("a.ts:User"))
    eq({ "User", "loadUser", "Profile", "App" }, names(g))
    eq({ "Profile -> App", "User -> loadUser", "loadUser -> Profile" }, edges(g))
    eq(3, g.nodes[g.order[4]].depth)
    eq(true, g.nodes[g.order[1]].root)
  end,

  ["a cycle is visited once and keeps its closing edge"] = function()
    local source, root = project(
      { "a.ts:ping", "a.ts:pong" },
      { ["a.ts:ping"] = { "a.ts:pong" }, ["a.ts:pong"] = { "a.ts:ping" } }
    )
    local g = graph.build(source, root("a.ts:ping"))
    eq({ "ping", "pong" }, names(g))
    eq({ "ping -> pong", "pong -> ping" }, edges(g))
    eq(2, source.calls)
  end,

  ["a symbol referencing itself adds nothing"] = function()
    local source, root = project({ "a.ts:fact" }, { ["a.ts:fact"] = { "a.ts:fact" } })
    local g = graph.build(source, root("a.ts:fact"))
    eq({ "fact" }, names(g))
    eq({}, g.edges)
  end,

  ["several references from one user make one edge"] = function()
    local source, root = project({ "a.ts:T", "b.ts:f" }, { ["a.ts:T"] = { "b.ts:f", "b.ts:f", "b.ts:f" } })
    local g = graph.build(source, root("a.ts:T"))
    eq({ "T -> f" }, edges(g))
  end,

  ["a diamond shares the common user"] = function()
    local source, root = project(
      { "a.ts:T", "b.ts:left", "b.ts:right", "c.ts:top" },
      { ["a.ts:T"] = { "b.ts:left", "b.ts:right" }, ["b.ts:left"] = { "c.ts:top" }, ["b.ts:right"] = { "c.ts:top" } }
    )
    local g = graph.build(source, root("a.ts:T"))
    eq({ "T", "left", "right", "top" }, names(g))
    eq({ "T -> left", "T -> right", "left -> top", "right -> top" }, edges(g))
  end,

  ["a reference outside every symbol becomes a file-scope node"] = function()
    local source, root = project({ "a.ts:T", "b.ts:f" }, { ["a.ts:T"] = { "main.ts", "main.ts", "b.ts:f" } })
    local g = graph.build(source, root("a.ts:T"))
    eq({ "T", "<main.ts>", "f" }, names(g))
    eq({ "T -> <main.ts>", "T -> f" }, edges(g))
  end,

  ["max_depth stops following users"] = function()
    local source, root = project(
      { "a.ts:A", "a.ts:B", "a.ts:C" },
      { ["a.ts:A"] = { "a.ts:B" }, ["a.ts:B"] = { "a.ts:C" } }
    )
    local g = graph.build(source, root("a.ts:A"), { max_depth = 1 })
    eq({ "A", "B" }, names(g))
  end,

  ["max_nodes truncates and says so"] = function()
    local source, root = project(
      { "a.ts:A", "a.ts:B", "a.ts:C", "a.ts:D" },
      { ["a.ts:A"] = { "a.ts:B", "a.ts:C", "a.ts:D" } }
    )
    local g = graph.build(source, root("a.ts:A"), { max_nodes = 2 })
    eq({ "A", "B" }, names(g))
    eq({ "A -> B" }, edges(g))
    eq(true, g.truncated)

    local full = graph.build(source, root("a.ts:A"))
    eq(false, full.truncated)
  end,
}
