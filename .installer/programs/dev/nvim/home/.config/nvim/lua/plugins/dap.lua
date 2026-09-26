-- Debugging (ADR 0140): nvim-dap + dap-ui. Adapters install as system packages,
-- never mason. The core-five come from the Language Registry (ADR 0141):
-- python (debugpy), go (delve), rust+c/cpp (codelldb), js/ts (vscode-js-debug).
-- Lazy: loads on the <leader>d keys only, so it costs nothing at startup.
return {
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      { "rcarriga/nvim-dap-ui", dependencies = { "nvim-neotest/nvim-nio" } },
      "mfussenegger/nvim-dap-python",
      "leoluz/nvim-dap-go",
    },
    keys = {
      {
        "<leader>db",
        function() require("dap").toggle_breakpoint() end,
        desc = "Debug: Toggle breakpoint",
      },
      {
        "<leader>dB",
        function()
          require("dap").set_breakpoint(vim.fn.input("Condition: "))
        end,
        desc = "Debug: Conditional breakpoint",
      },
      {
        "<leader>dc",
        function() require("dap").continue() end,
        desc = "Debug: Continue/Start",
      },
      {
        "<leader>di",
        function() require("dap").step_into() end,
        desc = "Debug: Step into",
      },
      {
        "<leader>do",
        function() require("dap").step_over() end,
        desc = "Debug: Step over",
      },
      {
        "<leader>dO",
        function() require("dap").step_out() end,
        desc = "Debug: Step out",
      },
      {
        "<leader>dr",
        function() require("dap").repl.toggle() end,
        desc = "Debug: REPL",
      },
      {
        "<leader>dl",
        function() require("dap").run_last() end,
        desc = "Debug: Run last",
      },
      {
        "<leader>dt",
        function() require("dap").terminate() end,
        desc = "Debug: Terminate",
      },
      {
        "<leader>du",
        function() require("dapui").toggle() end,
        desc = "Debug: Toggle UI",
      },
    },
    config = function()
      local dap = require("dap")
      local dapui = require("dapui")
      dapui.setup()

      -- Open the UI on session start, close it when the session ends.
      local L = dap.listeners.before
      L.attach.dapui_config = function() dapui.open() end
      L.launch.dapui_config = function() dapui.open() end
      L.event_terminated.dapui_config = function() dapui.close() end
      L.event_exited.dapui_config = function() dapui.close() end

      vim.fn.sign_define(
        "DapBreakpoint",
        { text = "●", texthl = "DiagnosticError" }
      )

      -- Which adapters the registry asks for, and the filetypes each debugs
      -- (both from the Language Registry, ADR 0140/0141).
      local langs = require("config.languages")
      local dft = langs.dap_filetypes()
      local want = {}
      for _, a in ipairs(langs.adapters()) do
        want[a] = true
      end

      -- python (debugpy): dap-python drives a debugpy-enabled python on PATH.
      if want.python then
        require("dap-python").setup("python")
      end

      -- go (delve): dap-go registers the delve adapter + go launch configs.
      if want.go then
        require("dap-go").setup()
      end

      -- rust + c/cpp (codelldb): one server adapter, a launch config per ft.
      if want.rust or want.c or want.cpp then
        dap.adapters.codelldb = {
          type = "server",
          port = "${port}",
          executable = { command = "codelldb", args = { "--port", "${port}" } },
        }
        local launch = {
          {
            name = "Launch (codelldb)",
            type = "codelldb",
            request = "launch",
            program = function()
              return vim.fn.input(
                "Path to executable: ",
                vim.fn.getcwd() .. "/",
                "file"
              )
            end,
            cwd = "${workspaceFolder}",
            stopOnEntry = false,
          },
        }
        -- codelldb serves these adapter keys; their filetypes come from dft.
        for _, key in ipairs({ "rust", "c", "cpp" }) do
          for _, ft in ipairs(dft[key] or {}) do
            dap.configurations[ft] = launch
          end
        end
      end

      -- js/ts (vscode-js-debug-bin): the pwa-node server adapter, served by
      -- the package's js-debug-dap. Defining it never errors, only launching
      -- a session with the package absent does.
      if want.js then
        dap.adapters["pwa-node"] = {
          type = "server",
          host = "localhost",
          port = "${port}",
          executable = { command = "js-debug-dap", args = { "${port}" } },
        }
        local node_launch = {
          {
            type = "pwa-node",
            request = "launch",
            name = "Launch file (pwa-node)",
            program = "${file}",
            cwd = "${workspaceFolder}",
          },
        }
        for _, ft in ipairs(dft.js or {}) do
          dap.configurations[ft] = node_launch
        end
      end
    end,
  },
}
