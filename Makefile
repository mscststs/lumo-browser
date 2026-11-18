# Lumo Browser — 常用任务入口
#
#   make help          # 列出所有目标
#   make doctor        # 环境预检
#   make build         # 增量构建（config a, FAST=1）
#   make apk           # 同上（别名，语义化）
#   make install       # 安装最新 APK（MIUI root 路径）
#   make verify        # 真机验收（30 项探针 + GATE）
#   make e2e           # Lumo 侧栏 + mock OpenAI 端到端
#
# 所有目标都是对 scripts/ 下脚本的薄封装，可直接调用脚本获得更细的控制。

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

CONFIG ?= a
FAST ?= 1
JOBS ?=
OUT_DIR ?=

export CONFIG FAST
ifneq ($(JOBS),)
export JOBS
endif
ifneq ($(OUT_DIR),)
export OUT_DIR
endif

S := scripts

.PHONY: help doctor fetch deps toolchain build build-rel apk install run verify e2e \
        flags-presets flags-push flags-clear cache-manifest cache-snapshot keys lint clean-artifacts

help: ## 列出所有目标
	@awk 'BEGIN {FS = ":.*## "; printf "\n用法: make <target> [CONFIG=a|b] [FAST=0|1]\n\n"} \
	     /^[a-zA-Z0-9_-]+:.*## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@printf "\n等价脚本：%s/README.md\n\n" "$(S)"

doctor: ## 环境预检（源码/工具链/设备/签名/磁盘）
	@$(S)/chromium/doctor.sh

fetch: ## 首次拉取 Chromium 源码（GCS tarball 见 README；git smart-HTTP 不可用）
	@$(S)/chromium/fetch.sh

deps: ## 安装 CIPD 依赖 + 工具链（NDK/SDK/JDK/clang）
	@$(S)/chromium/cipd-deps.sh
	@$(S)/chromium/toolchain.sh

toolchain: deps ## 同 deps

build: ## 增量构建（config a，FAST=1）
	@$(S)/chromium/build.sh $(CONFIG)

apk: build ## 同 build（别名）

build-rel: ## official 构建（验收/发布，FAST=0）
	@FAST=0 $(S)/chromium/build.sh $(CONFIG)

install: ## 安装最新 APK 到设备（MIUI root pm install）
	@$(S)/device/install.sh

run: ## 安装 + 装载扩展 + 启动 + 截图
	@$(S)/device/run.sh

verify: ## 真机验收：30 项探针 + 扩展/SW + 侧栏/关闭回归（产出 GATE）
	@$(S)/device/verify.sh

e2e: ## Lumo 侧栏 + 本地 mock OpenAI 端到端
	@$(S)/verify/lumo-e2e.sh

flags-presets: ## 列出可运行时切换的 feature
	@$(S)/chromium/flags.sh presets

flags-push: ## 推送命令行 flag（LUMO_FEATURES / LUMO_DISABLE_FEATURES / LUMO_FLAGS）
	@$(S)/chromium/flags.sh push

flags-clear: ## 清除设备命令行（回到上游默认行为）
	@$(S)/chromium/flags.sh clear

cache-manifest: ## 记录内核身份（版本/args/patch sha/APK sha）
	@$(S)/chromium/cache.sh manifest

cache-snapshot: ## 归档 out/ 目录（跨机器复用编译缓存）
	@$(S)/chromium/cache.sh snapshot

keys: ## 查看 dev 签名密钥（仅 debug）
	@$(S)/chromium/keys.sh status

lint: ## 仓库卫生检查（脚本语法/补丁编号/文档链接/skills）
	@bash tools/verify/check-repo.sh
	@bash tools/verify/check-static.sh

clean-artifacts: ## 清理可再生产物（APK/缓存 manifest/截图；保留 verify 证据）
	@rm -rf artifacts/cache artifacts/shots
	@printf 'removed: artifacts/cache artifacts/shots\n'
	@du -sh artifacts 2>/dev/null || true

.PHONY: help
