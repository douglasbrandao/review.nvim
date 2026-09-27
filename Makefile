.PHONY: test

test:
	NVIM_LOG_FILE=/tmp/review.nvim-test.log nvim --headless -u NONE -i NONE --cmd "lua vim.opt.runtimepath:append(vim.fn.getcwd())" -l tests/run.lua
