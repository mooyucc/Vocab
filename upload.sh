#!/bin/bash

# 自动上传到 GitHub 的脚本
# 仓库地址: https://github.com/mooyucc/Vocab

# 设置颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo -e "${GREEN}开始上传到 GitHub...${NC}"

# 检查是否已初始化 git 仓库
if [ ! -d ".git" ]; then
    echo -e "${YELLOW}初始化 Git 仓库...${NC}"
    git init
fi

# 检查是否已添加远程仓库
REMOTE_URL=$(git remote get-url origin 2>/dev/null)
if [ -z "$REMOTE_URL" ]; then
    echo -e "${YELLOW}添加远程仓库...${NC}"
    git remote add origin https://github.com/mooyucc/Vocab.git
else
    echo -e "${GREEN}远程仓库已存在: $REMOTE_URL${NC}"
    # 如果远程地址不对，更新它
    if [ "$REMOTE_URL" != "https://github.com/mooyucc/Vocab.git" ]; then
        echo -e "${YELLOW}更新远程仓库地址...${NC}"
        git remote set-url origin https://github.com/mooyucc/Vocab.git
    fi
fi

# 添加所有文件
echo -e "${YELLOW}添加文件到暂存区...${NC}"
git add .

# 检查是否有更改
if git diff --staged --quiet && git diff --quiet; then
    echo -e "${YELLOW}没有需要提交的更改${NC}"
    exit 0
fi

# 提交更改
echo -e "${YELLOW}提交更改...${NC}"
COMMIT_MESSAGE="自动提交: $(date '+%Y-%m-%d %H:%M:%S')"
git commit -m "$COMMIT_MESSAGE"

# 检查提交是否成功
if [ $? -ne 0 ]; then
    echo -e "${RED}提交失败！${NC}"
    exit 1
fi

# 获取当前分支名
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

# 推送到远程仓库
echo -e "${YELLOW}推送到远程仓库 (分支: $CURRENT_BRANCH)...${NC}"
git push -u origin "$CURRENT_BRANCH"

# 检查推送是否成功
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ 上传成功！${NC}"
else
    echo -e "${RED}推送失败！可能需要先拉取远程更改或检查权限${NC}"
    echo -e "${YELLOW}提示: 如果是第一次推送，可能需要使用: git push -u origin main${NC}"
    exit 1
fi
