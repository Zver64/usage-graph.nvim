local dot = require("usage-graph.dot")

local function has(text, needle)
  assert(text:find(needle, 1, true), ("expected to find %s in:\n%s"):format(needle, text))
end

local cwd = vim.fn.getcwd()
local function uri(rel)
  return vim.uri_from_fname(cwd .. "/" .. rel)
end

local function sample()
  local a, b, c = uri("src/model.ts") .. "#0:13", uri("src/api.ts") .. "#4:9", uri("src/main.ts")
  return {
    order = { a, b, c },
    nodes = {
      [a] = {
        key = a,
        uri = uri("src/model.ts"),
        pos = { line = 0, character = 13 },
        name = "User",
        kind = 5,
        depth = 0,
        root = true,
      },
      [b] = {
        key = b,
        uri = uri("src/api.ts"),
        pos = { line = 4, character = 9 },
        name = 'say "hi"',
        kind = 12,
        depth = 1,
      },
      [c] = { key = c, uri = uri("src/main.ts"), depth = 2, file = true },
    },
    edges = { { from = a, to = b }, { from = b, to = c } },
  }
end

return {
  ["every symbol is a node inside its file's cluster"] = function()
    local text = dot.generate(sample())
    has(text, "subgraph cluster_1 {")
    has(text, 'n1 [label="User", tooltip="Class · src/model.ts:1"')
    has(text, 'tooltip="Function · src/api.ts:5"')
  end,

  ["a cluster shows the file name and keeps the full path for hover"] = function()
    local pad = ("\194\160"):rep(4)
    local text = dot.generate(sample())
    has(text, 'label="' .. pad .. "model.ts" .. pad .. '"; tooltip="src/model.ts";')
    has(text, 'label="' .. pad .. "api.ts" .. pad .. '"; tooltip="src/api.ts";')
  end,

  ["files with the same name are told apart by their directories"] = function()
    local g = { order = {}, nodes = {}, edges = {} }
    for _, rel in ipairs({ "src/user/index.ts", "src/order/index.ts", "lib/user/index.ts", "src/app.ts" }) do
      g.order[#g.order + 1] = uri(rel)
      g.nodes[uri(rel)] = { key = uri(rel), uri = uri(rel), file = true }
    end
    local text = dot.generate(g)
    local pad = ("\194\160"):rep(4)
    for _, label in ipairs({ "src/user/index.ts", "order/index.ts", "lib/user/index.ts", "app.ts" }) do
      has(text, 'label="' .. pad .. label .. pad .. '";')
    end
  end,

  ["edges go from the used symbol to its user"] = function()
    local text = dot.generate(sample())
    has(text, "n1 -> n2;")
    has(text, "n2 -> n3;")
  end,

  ["the root is highlighted and file scope is marked"] = function()
    local text = dot.generate(sample())
    has(text, 'fillcolor="#ffd866"')
    has(text, 'n3 [label="(file scope)", style="rounded,dashed"')
  end,

  ["quotes in names are escaped"] = function()
    has(dot.generate(sample()), 'label="say \\"hi\\""')
  end,
}
