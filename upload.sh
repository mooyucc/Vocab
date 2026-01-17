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

# 检查远程分支是否存在
REMOTE_EXISTS=$(git ls-remote --heads origin "$CURRENT_BRANCH" 2>/dev/null | wc -l)

# 如果远程分支存在，先尝试拉取
if [ "$REMOTE_EXISTS" -gt 0 ]; then
    echo -e "${YELLOW}检测到远程分支，先拉取最新更改...${NC}"
    git pull origin "$CURRENT_BRANCH" --allow-unrelated-histories --no-edit 2>/dev/null
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}拉取失败，尝试合并不相关的历史...${NC}"
        git pull origin "$CURRENT_BRANCH" --allow-unrelated-histories --no-edit || {
            echo -e "${RED}拉取远程更改失败！请检查网络连接或手动解决冲突${NC}"
            exit 1
        }
    fi
fi

# 推送到远程仓库
echo -e "${YELLOW}推送到远程仓库 (分支: $CURRENT_BRANCH)...${NC}"
git push -u origin "$CURRENT_BRANCH"

# 检查推送是否成功
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ 上传成功！${NC}"
else
    echo -e "${RED}推送失败！${NC}"
    echo -e "${YELLOW}可能的原因：${NC}"
    echo -e "  1. 网络连接问题"
    echo -e "  2. 需要先拉取远程更改: git pull origin $CURRENT_BRANCH --allow-unrelated-histories"
    echo -e "  3. 需要配置 GitHub 认证（使用 Personal Access Token）"
    exit 1
fi
