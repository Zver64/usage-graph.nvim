local symbols = require("usage-graph.symbols")

local function eq(expected, actual)
  assert(vim.deep_equal(expected, actual), ("expected %s, got %s"):format(vim.inspect(expected), vim.inspect(actual)))
end

local function range(l1, c1, l2, c2)
  return { start = { line = l1, character = c1 }, ["end"] = { line = l2, character = c2 } }
end
local function pos(l, c)
  return { line = l, character = c }
end
local function path_of(sym)
  return sym and sym.path
end

local CLASS, METHOD, FUNCTION, VARIABLE = 5, 6, 12, 13

-- class Service extends Base {     (line 0)
--   run() {                        (line 1)
--     const user = load()          (line 2)
--   }                              (line 3)
--   stop() { ... }                 (lines 4-5)
-- }                                (line 6)
-- function main() {                (line 7)
--   const helper = () => { ... }   (lines 8-10)
-- }                                (line 11)
local hierarchical = {
  {
    name = "Service",
    kind = CLASS,
    range = range(0, 0, 6, 1),
    selectionRange = range(0, 6, 0, 13),
    children = {
      {
        name = "run",
        kind = METHOD,
        range = range(1, 2, 3, 3),
        selectionRange = range(1, 2, 1, 5),
        children = {
          { name = "user", kind = VARIABLE, range = range(2, 10, 2, 23), selectionRange = range(2, 10, 2, 14) },
        },
      },
      { name = "stop", kind = METHOD, range = range(4, 2, 5, 3), selectionRange = range(4, 2, 4, 6) },
    },
  },
  {
    name = "main",
    kind = FUNCTION,
    range = range(7, 0, 11, 1),
    selectionRange = range(7, 9, 7, 13),
    children = {
      { name = "helper", kind = FUNCTION, range = range(8, 8, 10, 3), selectionRange = range(8, 8, 8, 14) },
    },
  },
}

return {
  ["a reference inside a method belongs to the method, not the class"] = function()
    local roots = symbols.normalize(hierarchical)
    eq("Service.stop", path_of(symbols.enclosing(roots, pos(4, 10))))
  end,

  ["locals of a function are its implementation detail"] = function()
    local roots = symbols.normalize(hierarchical)
    -- `load()` in `const user = load()` is used by run(), not by `user`.
    eq("Service.run", path_of(symbols.enclosing(roots, pos(2, 17))))
    -- Same for a function nested in a function.
    eq("main", path_of(symbols.enclosing(roots, pos(9, 4))))
  end,

  ["a reference in the class header belongs to the class"] = function()
    local roots = symbols.normalize(hierarchical)
    eq("Service", path_of(symbols.enclosing(roots, pos(0, 22))))
  end,

  ["a position outside every symbol has no enclosing entity"] = function()
    local roots = symbols.normalize(hierarchical)
    eq(nil, symbols.enclosing(roots, pos(20, 0)))
  end,

  ["at_selection finds a symbol at any depth by its name position only"] = function()
    local roots = symbols.normalize(hierarchical)
    eq("Service.run", path_of(symbols.at_selection(roots, pos(1, 3))))
    eq("Service.run.user", path_of(symbols.at_selection(roots, pos(2, 12))))
    eq(nil, symbols.at_selection(roots, pos(2, 17)))
  end,

  ["flat symbols are nested by their ranges"] = function()
    local lines = { "class Service:", "    def run(self):", "        load()", "", "def main():", "    pass" }
    local function info(name, kind, container, r)
      return { name = name, kind = kind, containerName = container, location = { uri = "file:///a.py", range = r } }
    end
    -- Deliberately out of order.
    local flat = {
      info("run", METHOD, "Service", range(1, 4, 2, 14)),
      info("main", FUNCTION, nil, range(4, 0, 5, 8)),
      info("Service", CLASS, nil, range(0, 0, 2, 14)),
    }
    local roots = symbols.normalize(flat, {
      get_line = function(lnum)
        return lines[lnum + 1]
      end,
    })
    eq({ "Service", "main" }, vim.tbl_map(path_of, roots))
    eq("Service.run", path_of(symbols.enclosing(roots, pos(2, 8))))
    eq("main", path_of(symbols.enclosing(roots, pos(5, 4))))
  end,

  ["flat symbols get their name position from the text"] = function()
    local lines = { "// comment", "func Handle(w Writer) {", "}" }
    local flat = {
      { name = "Handle", kind = FUNCTION, location = { uri = "file:///a.go", range = range(1, 0, 2, 1) } },
    }
    local roots = symbols.normalize(flat, {
      get_line = function(lnum)
        return lines[lnum + 1]
      end,
    })
    eq(range(1, 5, 1, 11), roots[1].selection)
    eq("Handle", path_of(symbols.at_selection(roots, pos(1, 7))))
  end,

  ["flat symbol name positions are in the server's encoding"] = function()
    local flat = {
      { name = "x", kind = VARIABLE, location = { uri = "file:///a.py", range = range(0, 0, 0, 12) } },
    }
    local roots = symbols.normalize(flat, {
      encoding = "utf-16",
      get_line = function()
        return "ж = 1; x = 2"
      end,
    })
    -- "ж" is two bytes but one UTF-16 unit.
    eq(range(0, 7, 0, 8), roots[1].selection)
  end,
}
