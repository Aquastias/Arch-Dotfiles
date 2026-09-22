-- Editor options + provider gating.
local g = vim.g
local opt = vim.opt

g.mapleader = " "
-- Distinct from leader so filetype-local maps (e.g. orgmode) don't collide.
g.maplocalleader = ","

-- Follow-Noctalia toggle (ADR 0136). Default off → static Catppuccin Mocha
-- Sapphire. The live-follow path (ticket 07) reads this at startup.
g.follow_noctalia = false

-- Silence providers no shipped plugin needs, so :checkhealth stays quiet
-- (ADR 0135 acceptance bar).
g.loaded_perl_provider = 0
g.loaded_ruby_provider = 0
g.loaded_node_provider = 0
g.loaded_python3_provider = 0

opt.termguicolors = true
opt.number = true
opt.relativenumber = true
opt.signcolumn = "yes"
opt.cursorline = true

-- Indent fallbacks; per-project width comes from editorconfig (built in).
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.smartindent = true

opt.wrap = false
opt.ignorecase = true
opt.smartcase = true
opt.undofile = true
opt.splitright = true
opt.splitbelow = true
opt.scrolloff = 8
opt.updatetime = 200
opt.clipboard = "unnamedplus"
opt.completeopt = "menu,menuone,noselect"

-- Folding defaults (ufo arrives in a later ticket; keep folds open for now).
opt.foldcolumn = "0"
opt.foldlevel = 99
opt.foldlevelstart = 99
opt.foldenable = true
