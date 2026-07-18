-- Plenary busted harness bootstrap. Prepends plenary + repo root to rtp.
vim.opt.rtp:prepend(vim.fn.expand "~/.local/share/nvim/lazy/plenary.nvim")
vim.opt.rtp:prepend(vim.uv.cwd())
vim.cmd "runtime! plugin/plenary.vim"
