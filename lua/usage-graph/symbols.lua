-- Pure helpers over `textDocument/documentSymbol` results.
--
-- Both response shapes (hierarchical DocumentSymbol[] and flat SymbolInformation[])
-- become one tree of:
--   { name, path, kind, range, selection, children }
-- where `path` is the qualified name ("Class.method") and `selection` is the range
-- of the symbol's name, i.e. the position to ask references for.

local M = {}

local K = vim.lsp.protocol.SymbolKind

-- Kinds that only group other entities. A reference inside one of them belongs
-- to the member it is in (a method of a class), not to the group itself.
-- Anything else (a function, a variable, a field) is an entity of its own:
-- what is declared inside it is its implementation detail.
local CONTAINER = {
  [K.File] = true,
  [K.Module] = true,
  [K.Namespace] = true,
  [K.Package] = true,
  [K.Class] = true,
  [K.Interface] = true,
  [K.Struct] = true,
  [K.Enum] = true,
}

local function before(a, b)
  return a.line < b.line or (a.line == b.line and a.character < b.character)
end

local function contains(range, pos)
  return not before(pos, range.start) and not before(range["end"], pos)
end

local function encloses(outer, inner)
  return not before(inner.start, outer.start) and not before(outer["end"], inner["end"])
end

-- SymbolInformation has no selectionRange: look the name up in the text.
local function find_name(name, range, opts)
  local get_line, encoding = opts.get_line, opts.encoding or "utf-16"
  local short = name:match("[%w_]+$")
  if get_line then
    local last = math.min(range["end"].line, range.start.line + 20)
    for lnum = range.start.line, last do
      local text = get_line(lnum)
      if not text then
        break
      end
      local init = 1
      if lnum == range.start.line then
        init = vim.str_byteindex(text, encoding, range.start.character, false) + 1
      end
      for _, needle in ipairs({ name, short }) do
        local s, e = text:find(needle, init, true)
        if s then
          return {
            start = { line = lnum, character = vim.str_utfindex(text, encoding, s - 1, false) },
            ["end"] = { line = lnum, character = vim.str_utfindex(text, encoding, e, false) },
          }
        end
      end
    end
  end
  return { start = range.start, ["end"] = range.start }
end

local function from_hierarchy(result)
  local function convert(sym, parent_path)
    local path = parent_path and (parent_path .. "." .. sym.name) or sym.name
    local node = {
      name = sym.name,
      path = path,
      kind = sym.kind,
      range = sym.range,
      selection = sym.selectionRange,
      children = {},
    }
    for _, child in ipairs(sym.children or {}) do
      node.children[#node.children + 1] = convert(child, path)
    end
    return node
  end
  return vim.tbl_map(convert, result)
end

-- A flat list carries no nesting: restore it from the ranges.
local function from_flat(result, opts)
  local nodes = {}
  for _, sym in ipairs(result) do
    local container = sym.containerName
    nodes[#nodes + 1] = {
      name = sym.name,
      path = (container and container ~= "") and (container .. "." .. sym.name) or sym.name,
      kind = sym.kind,
      range = sym.location.range,
      selection = find_name(sym.name, sym.location.range, opts),
      children = {},
    }
  end
  table.sort(nodes, function(a, b)
    if before(a.range.start, b.range.start) then
      return true
    end
    return not before(b.range.start, a.range.start) and before(b.range["end"], a.range["end"])
  end)
  local roots, stack = {}, {}
  for _, node in ipairs(nodes) do
    while stack[#stack] and not encloses(stack[#stack].range, node.range) do
      stack[#stack] = nil
    end
    local siblings = stack[#stack] and stack[#stack].children or roots
    siblings[#siblings + 1] = node
    stack[#stack + 1] = node
  end
  return roots
end

---@param result table[]? DocumentSymbol[] | SymbolInformation[]
---@param opts? { get_line?: fun(lnum: integer): string?, encoding?: string }
---@return table[] roots
function M.normalize(result, opts)
  if not result or not result[1] then
    return {}
  end
  if result[1].location then
    return from_flat(result, opts or {})
  end
  return from_hierarchy(result)
end

-- Among `list`, the symbol whose `field` range is the tightest around `pos`.
local function tightest(list, pos, field, best)
  for _, sym in ipairs(list) do
    local range = sym[field]
    if contains(range, pos) and (not best or encloses(best[field], range)) then
      best = sym
    end
  end
  return best
end

--- The entity a reference at `pos` belongs to: descends through containers
--- (class -> method) and stops at the first symbol that is not one.
--- Returns nil when `pos` is at file scope.
---
--- TODO: a member does not make its container a user. With `struct Repo { last User }`
--- the graph of `User` gets `Repo.last` but not `Repo`, so code that uses `Repo`
--- without touching `last` is missed. A "member -> its container" edge would fix
--- that, but then changing any method drags in every user of the class. Undecided.
function M.enclosing(roots, pos)
  local node = tightest(roots, pos, "range")
  while node and CONTAINER[node.kind] do
    local child = tightest(node.children or {}, pos, "range")
    if not child then
      break
    end
    node = child
  end
  return node
end

--- The symbol (at any depth) whose name is at `pos`.
function M.at_selection(roots, pos)
  local best
  local function visit(list)
    best = tightest(list, pos, "selection", best)
    for _, sym in ipairs(list) do
      visit(sym.children or {})
    end
  end
  visit(roots)
  return best
end

return M
