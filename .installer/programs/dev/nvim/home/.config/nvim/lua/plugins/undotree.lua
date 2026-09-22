-- undotree (ADR 0135): visualise + navigate the undo history with a diff.
return {
  "mbbill/undotree",
  cmd = "UndotreeToggle",
  keys = {
    -- <leader>U: <leader>u is the ui/toggle group (uC/uN/uh).
    { "<leader>U", "<cmd>UndotreeToggle<cr>", desc = "Undotree" },
  },
}
