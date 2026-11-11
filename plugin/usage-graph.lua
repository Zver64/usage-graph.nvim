vim.api.nvim_create_user_command("UsageGraph", function()
  require("usage-graph").show()
end, { desc = "Graph of everything that uses the symbol under the cursor" })
