PLENARY_DIR := $(HOME)/.local/share/nvim/lazy/plenary.nvim
DAP_DIR := $(HOME)/.local/share/nvim/lazy/nvim-dap
IMAGE_DIR := $(HOME)/.local/share/nvim/lazy/image.nvim
# Override to test against a development checkout: make test IMAGE_VIEW_DIR=~/projects/image-view.nvim
IMAGE_VIEW_DIR ?= $(HOME)/.local/share/nvim/lazy/image-view.nvim
export IMAGE_VIEW_DIR

.PHONY: test test-python test-cpp test-cpp-dapui demo-setup-python demo-setup-cpp

test:
	nvim --headless \
		--noplugin \
		-u NORC \
		--cmd "set rtp+=$(PLENARY_DIR)" \
		--cmd "set rtp+=$(DAP_DIR)" \
		--cmd "set rtp+=$(IMAGE_DIR)" \
		--cmd "set rtp+=$(IMAGE_VIEW_DIR)" \
		--cmd "set rtp+=." \
		-c "lua require('plenary.test_harness').test_directory('tests', { minimal_init = 'tests/minimal_init.lua' })"

demo-setup-python:
	cd demo/python && ./setup.sh

demo-setup-cpp:
	cd demo/cpp && bazel build //:demo

test-python: demo-setup-python
	cd demo/python && nvim --headless \
		--noplugin \
		-u ../../tests/minimal_init.lua \
		--cmd "set rtp+=../../" \
		-S test_integration.lua

test-cpp: demo-setup-cpp
	cd demo/cpp && nvim --headless \
		--noplugin \
		-u ../../tests/minimal_init.lua \
		--cmd "set rtp+=../../" \
		-S test_integration.lua

test-cpp-dapui: demo-setup-cpp
	cd demo/cpp && nvim --headless \
		--noplugin \
		-u ../../tests/minimal_init.lua \
		--cmd "set rtp+=../../" \
		-S test_dapui.lua
