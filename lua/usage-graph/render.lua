-- Graph -> SVG (via Graphviz `dot`) -> an HTML page.
-- How the page is shown is a separate step, so other viewers can be added later.

local dot = require("usage-graph.dot")

local M = {}

local function escape_html(s)
  return (s:gsub("[&<>]", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;" }))
end

--- Renders the graph into an HTML file.
---@param graph table
---@param callback fun(err: string?, path: string?)
function M.write(graph, callback)
  if vim.fn.executable("dot") ~= 1 then
    return callback("Graphviz `dot` is not in PATH")
  end
  vim.system(
    { "dot", "-Tsvg" },
    { stdin = dot.generate(graph), text = true },
    vim.schedule_wrap(function(res)
      if res.code ~= 0 then
        return callback("dot failed: " .. vim.trim(res.stderr or ""))
      end
      local svg = res.stdout:sub(res.stdout:find("<svg", 1, true) or 1)
      local name = graph.nodes[graph.order[1]].name
      local dir = vim.fs.joinpath(vim.fn.stdpath("cache"), "usage-graph")
      vim.fn.mkdir(dir, "p")
      local path = vim.fs.joinpath(dir, (name:gsub("[^%w_.-]", "_")) .. ".html")
      local html = ('<!doctype html>\n<meta charset="utf-8">\n<title>%s — usage graph</title>\n%s'):format(
        escape_html(name),
        svg
      )
      local file, err = io.open(path, "w")
      if not file then
        return callback(err)
      end
      file:write(html)
      file:close()
      callback(nil, path)
    end)
  )
end

--- Opens the rendered page in the system browser.
function M.open(path)
  vim.ui.open(path)
end

return M
