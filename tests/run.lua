-- Test runner: `nvim --clean -l tests/run.lua` from the plugin root.
-- Every tests/*_spec.lua returns a table { ["test name"] = function() ... end }.

local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
package.path = root .. "/tests/?.lua;" .. package.path

local failed, total = 0, 0
for _, file in ipairs(vim.fn.sort(vim.fn.glob(root .. "/tests/*_spec.lua", false, true))) do
  local spec = dofile(file)
  local names = vim.tbl_keys(spec)
  table.sort(names)
  for _, name in ipairs(names) do
    total = total + 1
    local ok, err = xpcall(spec[name], debug.traceback)
    if ok then
      print(("ok    %s: %s"):format(vim.fs.basename(file), name))
    else
      failed = failed + 1
      print(("FAIL  %s: %s\n%s"):format(vim.fs.basename(file), name, err))
    end
  end
end

print(("\n%d tests, %d failed"):format(total, failed))
os.exit(failed == 0 and 0 or 1)
