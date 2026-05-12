#!/bin/bash

# Jenkins Build Trigger Script
# Jenkins requires POST requests to trigger builds — GET requests are rejected.
#
# Usage:
#   ./trigger-build.sh                          # uses defaults below
#   JENKINS_USER=admin JENKINS_TOKEN=xxx ./trigger-build.sh
#   ./trigger-build.sh --url http://host:8080 --job my-job

set -e

# ── Defaults (override via environment variables or flags) ──────────────────
JENKINS_URL="${JENKINS_URL:-http://localhost:8080}"
JOB_NAME="${JOB_NAME:-jenkins-maven-project}"
JENKINS_USER="${JENKINS_USER:-admin}"
JENKINS_TOKEN="${JENKINS_TOKEN:-}"   # Jenkins API token (preferred over password)
BUILD_TOKEN="${BUILD_TOKEN:-}"       # Optional per-project remote trigger token

# ── Argument parsing ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --url)    JENKINS_URL="$2"; shift 2 ;;
        --job)    JOB_NAME="$2";    shift 2 ;;
        --user)   JENKINS_USER="$2"; shift 2 ;;
        --token)  JENKINS_TOKEN="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "================================================"
echo "Jenkins Build Trigger"
echo "================================================"
echo "Jenkins URL : ${JENKINS_URL}"
echo "Job Name    : ${JOB_NAME}"
echo ""

# ── Helper: POST request ─────────────────────────────────────────────────────
post_build() {
    local url="$1"
    local auth_args=()

    if [[ -n "$JENKINS_TOKEN" ]]; then
        auth_args=(-u "${JENKINS_USER}:${JENKINS_TOKEN}")
    fi

    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        "${auth_args[@]}" \
        "${url}")

    echo "$HTTP_CODE"
}

# ── Method 1: Trigger with API token (recommended) ───────────────────────────
if [[ -n "$JENKINS_TOKEN" ]]; then
    echo "Triggering build with API token (POST)..."
    CRUMB=$(curl -s -u "${JENKINS_USER}:${JENKINS_TOKEN}" \
        "${JENKINS_URL}/crumbIssuer/api/json" | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d['crumb'])" 2>/dev/null || echo "")

    if [[ -n "$CRUMB" ]]; then
        CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -X POST \
            -u "${JENKINS_USER}:${JENKINS_TOKEN}" \
            -H "Jenkins-Crumb:${CRUMB}" \
            "${JENKINS_URL}/job/${JOB_NAME}/build")
    else
        CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -X POST \
            -u "${JENKINS_USER}:${JENKINS_TOKEN}" \
            "${JENKINS_URL}/job/${JOB_NAME}/build")
    fi

    if [[ "$CODE" == "201" || "$CODE" == "200" ]]; then
        echo -e "${GREEN}✓ Build triggered successfully (HTTP $CODE)${NC}"
        echo "Monitor at: ${JENKINS_URL}/job/${JOB_NAME}/"
        exit 0
    else
        echo -e "${RED}✗ Build trigger failed (HTTP $CODE)${NC}"
        exit 1
    fi

# ── Method 2: Trigger with per-project remote build token ────────────────────
elif [[ -n "$BUILD_TOKEN" ]]; then
    echo "Triggering build with remote build token (POST)..."
    CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        "${JENKINS_URL}/job/${JOB_NAME}/build?token=${BUILD_TOKEN}")

    if [[ "$CODE" == "201" || "$CODE" == "200" ]]; then
        echo -e "${GREEN}✓ Build triggered successfully (HTTP $CODE)${NC}"
        echo "Monitor at: ${JENKINS_URL}/job/${JOB_NAME}/"
        exit 0
    else
        echo -e "${RED}✗ Build trigger failed (HTTP $CODE)${NC}"
        exit 1
    fi

# ── No credentials: print usage ──────────────────────────────────────────────
else
    echo -e "${YELLOW}No credentials provided. Use one of the following methods:${NC}"
    echo ""
    echo "Method 1 — API token (recommended):"
    echo "  Get your token at: ${JENKINS_URL}/user/<username>/configure"
    echo ""
    echo "  JENKINS_USER=admin JENKINS_TOKEN=<api-token> ./trigger-build.sh"
    echo ""
    echo "  Or with curl directly (always use -X POST):"
    echo "  curl -X POST -u admin:<api-token> \\"
    echo "       \$(curl -s -u admin:<api-token> ${JENKINS_URL}/crumbIssuer/api/json \\"
    echo "         | python3 -c \"import sys,json; d=json.load(sys.stdin); print('-H ' + d['crumbRequestField'] + ':' + d['crumb'])\") \\"
    echo "       ${JENKINS_URL}/job/${JOB_NAME}/build"
    echo ""
    echo "Method 2 — Per-project build token:"
    echo "  1. In Jenkins: Job > Configure > Build Triggers > Trigger builds remotely"
    echo "  2. Set an Authentication Token (e.g. my-secret-token)"
    echo "  3. Trigger with POST (NOT GET):"
    echo "     curl -X POST \"${JENKINS_URL}/job/${JOB_NAME}/build?token=my-secret-token\""
    echo ""
    echo "  BUILD_TOKEN=my-secret-token ./trigger-build.sh"
    echo ""
    echo -e "${RED}NOTE: Using a browser URL or GET request will return the error:${NC}"
    echo "  'You must use POST method to trigger builds'"
    exit 1
fi
