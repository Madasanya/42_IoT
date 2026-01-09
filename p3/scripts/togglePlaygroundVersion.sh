#!/bin/bash

# Script to toggle playground version between v1 and v2 in a git repository
# Usage: ./togglePlaygroundVersion.sh /path/to/repo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if path argument is provided
if [ $# -eq 0 ]; then
    echo -e "${RED}Error: No repository path provided${NC}"
    echo "Usage: $0 /path/to/repo"
    exit 1
fi

REPO_PATH="$1"

# Verify the path exists
if [ ! -d "$REPO_PATH" ]; then
    echo -e "${RED}Error: Directory '$REPO_PATH' does not exist${NC}"
    exit 1
fi

# Check if it's a git repository
if [ ! -d "$REPO_PATH/.git" ]; then
    echo -e "${RED}Error: '$REPO_PATH' is not a git repository${NC}"
    exit 1
fi

echo -e "${YELLOW}Searching for playground version in repository...${NC}"

# Find all deployment.yaml files with playground image
DEPLOYMENT_FILES=$(find "$REPO_PATH" -name "*.yaml" -o -name "*.yml" | xargs grep -l "wil42/playground" 2>/dev/null || true)

if [ -z "$DEPLOYMENT_FILES" ]; then
    echo -e "${RED}Error: No playground deployment files found${NC}"
    exit 1
fi

# Detect current version
CURRENT_VERSION=""
for FILE in $DEPLOYMENT_FILES; do
    if grep -q "wil42/playground:v1" "$FILE"; then
        CURRENT_VERSION="v1"
        break
    elif grep -q "wil42/playground:v2" "$FILE"; then
        CURRENT_VERSION="v2"
        break
    fi
done

if [ -z "$CURRENT_VERSION" ]; then
    echo -e "${RED}Error: Could not detect current playground version${NC}"
    exit 1
fi

# Determine new version
if [ "$CURRENT_VERSION" == "v1" ]; then
    NEW_VERSION="v2"
else
    NEW_VERSION="v1"
fi

echo -e "${GREEN}Current version: ${CURRENT_VERSION}${NC}"
echo -e "${GREEN}New version: ${NEW_VERSION}${NC}"

# Change directory to repo
cd "$REPO_PATH"

# Toggle version in all files
echo -e "${YELLOW}Updating files...${NC}"
for FILE in $DEPLOYMENT_FILES; do
    if grep -q "wil42/playground:${CURRENT_VERSION}" "$FILE"; then
        sed -i "s|wil42/playground:${CURRENT_VERSION}|wil42/playground:${NEW_VERSION}|g" "$FILE"
        echo -e "${GREEN}✓ Updated: $FILE${NC}"
    fi
done

# Git operations
echo -e "${YELLOW}Committing changes...${NC}"
git add .
git commit -m "Toggle playground version from ${CURRENT_VERSION} to ${NEW_VERSION}"

echo -e "${GREEN}✓ Changes committed${NC}"

# Ask if user wants to push
echo -e "${YELLOW}Do you want to push changes to remote? (y/n)${NC}"
read -r PUSH_CONFIRM

if [[ "$PUSH_CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Pushing to remote...${NC}"
    git push
    echo -e "${GREEN}✓ Changes pushed to remote${NC}"
else
    echo -e "${YELLOW}Changes not pushed. Run 'git push' manually when ready.${NC}"
fi

echo -e "${GREEN}✓ Version toggle complete!${NC}"
echo -e "${GREEN}Playground version changed from ${CURRENT_VERSION} to ${NEW_VERSION}${NC}"
