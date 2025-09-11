# Troubleshooting Guide

This comprehensive guide helps resolve common issues with Claude Code PM and its Jira integration. Each section includes diagnostic steps, solutions, and preventive measures.

## Table of Contents

- [Quick Diagnostic Commands](#quick-diagnostic-commands)
- [Authentication Issues](#authentication-issues)
- [Connection Problems](#connection-problems)
- [Sync Issues](#sync-issues)
- [Search Problems](#search-problems)
- [Performance Issues](#performance-issues)
- [Configuration Problems](#configuration-problems)
- [Git Integration Issues](#git-integration-issues)
- [MCP Tool Errors](#mcp-tool-errors)
- [Data Consistency Issues](#data-consistency-issues)
- [Common Error Messages](#common-error-messages)
- [Recovery Procedures](#recovery-procedures)
- [Debug Mode](#debug-mode)

---

## Quick Diagnostic Commands

Run these commands to quickly identify system issues:

```bash
# Check overall system health
/pm:validate

# Test Jira connection
/pm:search --jira "test" --limit 1

# Check authentication status
cat ~/.cache/ccpm-jira/auth_state

# Verify configuration
cat claude/settings.local.json | jq '.jira'

# Check for sync conflicts
find .claude/epics -name "*.conflict" -type f

# Test MCP availability
claude mcp__atlassian__atlassianUserInfo

# Check cache status
du -sh ~/.cache/ccpm-jira/
ls -la ~/.cache/ccpm-jira/searches/ | wc -l
```

---

## Authentication Issues

### Problem: Jira Authentication Failed

**Symptoms:**
- `❌ JQL search requires Atlassian authentication`
- `401 Unauthorized` errors
- `Failed to get Atlassian cloud ID`

**Solution 1: Re-authenticate with MCP**
```bash
# Clear authentication cache
rm -f ~/.cache/ccpm-jira/auth_state

# Re-authenticate
claude login

# Verify authentication
claude mcp__atlassian__atlassianUserInfo
```

**Solution 2: Check API Token**
```bash
# Verify environment variables
echo $JIRA_API_TOKEN
echo $JIRA_USER_EMAIL
echo $JIRA_SITE_URL

# Re-export if missing
export JIRA_API_TOKEN="your-token-here"
export JIRA_USER_EMAIL="your.email@company.com"
export JIRA_SITE_URL="https://company.atlassian.net"
```

**Solution 3: Validate Token Permissions**
1. Log into Atlassian account settings
2. Navigate to Security → API tokens
3. Ensure token has these permissions:
   - Browse projects
   - Create issues
   - Edit issues
   - Transition issues
   - Add comments

### Problem: GitHub CLI Authentication Failed

**Symptoms:**
- `gh: command not found`
- `error: You must be logged in to run this command`

**Solution:**
```bash
# Install GitHub CLI if missing
brew install gh  # macOS
# or
sudo apt install gh  # Ubuntu/Debian

# Authenticate
gh auth login

# Verify
gh auth status
```

---

## Connection Problems

### Problem: Cannot Connect to Jira

**Symptoms:**
- `Failed to connect to Atlassian`
- `Network timeout`
- `DNS resolution failed`

**Solution 1: Check Network**
```bash
# Test connectivity
ping atlassian.net
curl -I https://your-site.atlassian.net

# Check proxy settings
echo $HTTP_PROXY
echo $HTTPS_PROXY

# Test with proxy
curl -x $HTTP_PROXY https://your-site.atlassian.net
```

**Solution 2: Verify Site URL**
```bash
# Check configuration
grep "site_url" claude/settings.local.json

# Test direct access
curl -H "Authorization: Basic $(echo -n $JIRA_USER_EMAIL:$JIRA_API_TOKEN | base64)" \
     "https://your-site.atlassian.net/rest/api/3/myself"
```

**Solution 3: Firewall/VPN Issues**
- Check if behind corporate firewall
- Verify VPN is connected if required
- Add proxy configuration to settings:

```json
{
  "jira": {
    "proxy": {
      "host": "proxy.company.com",
      "port": 8080,
      "auth": "username:password"
    }
  }
}
```

---

## Sync Issues

### Problem: Bidirectional Sync Conflicts

**Symptoms:**
- `⚠️ Conflicts detected between local and Jira data`
- Status mismatch warnings
- Sync operations fail

**Solution 1: Force Local Precedence**
```bash
# Force sync with local data taking precedence
/pm:issue-sync 1234 --force

# For epic-level sync
/pm:epic-sync user-authentication --force-local
```

**Solution 2: Manual Conflict Resolution**
```bash
# 1. Check conflict details
/pm:issue-sync 1234 --dry-run

# 2. View conflict report
cat .claude/epics/[epic-name]/conflicts/1234.json

# 3. Edit local file to resolve
vim .claude/epics/[epic-name]/1234.md

# 4. Retry sync
/pm:issue-sync 1234
```

**Solution 3: Reset Sync State**
```bash
# Clear cache for specific issue
rm -rf .claude/epics/[epic-name]/jira-cache/1234.json

# Re-initialize sync
/pm:issue-sync 1234 --init
```

### Problem: Partial Sync Failures

**Symptoms:**
- Some issues sync, others fail
- Incomplete epic updates
- Missing Jira links

**Solution:**
```bash
# Run validation
/pm:validate --fix

# Batch retry failed syncs
for issue in $(pm:validate | grep "missing Jira link" | awk '{print $2}'); do
  /pm:issue-sync $issue --retry
done

# Force full epic refresh
/pm:epic-refresh [epic-name] --full
```

---

## Search Problems

### Problem: Natural Language Search Not Working

**Symptoms:**
- `❌ Natural language search failed`
- Empty search results
- MCP tool unavailable

**Solution 1: Check MCP Installation**
```bash
# Verify Claude CLI
which claude

# Test MCP search tool
claude mcp__atlassian__search --query "test"

# Check MCP server status
ps aux | grep mcp-server
```

**Solution 2: Fallback to JQL**
```bash
# Force JQL search
/pm:search --jql "text ~ 'search term'"

# Or use hybrid mode
/pm:search --hybrid "your search query"
```

### Problem: JQL Syntax Errors

**Symptoms:**
- `Invalid JQL query`
- `Field 'X' does not exist`

**Solution:**
```bash
# Validate JQL syntax
/pm:search --validate-jql "your query"

# Get available fields
/pm:search --list-fields

# Use query builder
/pm:search --build-jql
```

### Problem: Search Cache Issues

**Symptoms:**
- Stale search results
- Cache growing too large
- Slow search performance

**Solution:**
```bash
# Clear search cache
rm -rf ~/.cache/ccpm-jira/searches/*

# Disable cache temporarily
/pm:search --no-cache "query"

# Set cache TTL
export CCPM_CACHE_TTL=60  # 60 seconds

# View cache statistics
/pm:search --cache-stats
```

---

## Performance Issues

### Problem: Slow Command Execution

**Symptoms:**
- Commands take >10 seconds
- Timeouts during operations
- High CPU/memory usage

**Solution 1: Optimize Cache**
```bash
# Check cache size
du -sh ~/.cache/ccpm-jira/

# Clean old cache entries
find ~/.cache/ccpm-jira -mtime +7 -delete

# Limit cache size
export CCPM_MAX_CACHE_MB=100
```

**Solution 2: Reduce API Calls**
```bash
# Increase result limits
/pm:search --max-results 100

# Use batch operations
/pm:epic-sync --batch

# Enable request pooling
export CCPM_ENABLE_POOLING=true
```

**Solution 3: Profile Performance**
```bash
# Enable timing
export CCPM_TIMING=true

# Run with profiling
time /pm:epic-list --jira-sync

# Check slow queries
/pm:search --explain "complex query"
```

### Problem: Memory Leaks

**Symptoms:**
- Increasing memory usage over time
- System becomes unresponsive
- Out of memory errors

**Solution:**
```bash
# Monitor memory usage
while true; do
  ps aux | grep "pm:" | awk '{print $4}'
  sleep 5
done

# Set memory limits
export CCPM_MAX_MEMORY_MB=512

# Enable garbage collection logging
export CCPM_GC_LOG=true
```

---

## Configuration Problems

### Problem: Invalid Configuration File

**Symptoms:**
- `Failed to parse settings.local.json`
- Commands fail with config errors

**Solution 1: Validate JSON**
```bash
# Check syntax
jq '.' claude/settings.local.json

# Pretty print and fix
jq '.' claude/settings.local.json > temp.json
mv temp.json claude/settings.local.json
```

**Solution 2: Reset Configuration**
```bash
# Backup current config
cp claude/settings.local.json claude/settings.backup.json

# Re-initialize
/pm:init --reset-config
```

### Problem: Custom Field Mapping Issues

**Symptoms:**
- Custom fields not syncing
- `Field 'customfield_XXXXX' not found`

**Solution:**
```bash
# List available custom fields
/pm:search --list-custom-fields

# Update mapping
cat > claude/settings.local.json << EOF
{
  "jira": {
    "custom_fields": {
      "story_points": "customfield_10001",
      "github_url": "customfield_10100"
    }
  }
}
EOF
```

---

## Git Integration Issues

### Problem: Branch Creation Fails

**Symptoms:**
- `Failed to create branch`
- `Reference already exists`

**Solution:**
```bash
# Check existing branches
git branch -a | grep PROJ-

# Force new branch
git checkout -B PROJ-123-feature-name

# Clean up old branches
git branch -d $(git branch --merged | grep -v main)
```

### Problem: Worktree Conflicts

**Symptoms:**
- `Worktree already exists`
- Cannot switch between epics

**Solution:**
```bash
# List worktrees
git worktree list

# Remove broken worktree
git worktree remove ../epic-name

# Prune worktree list
git worktree prune
```

---

## MCP Tool Errors

### Problem: MCP Server Not Running

**Symptoms:**
- All MCP commands fail
- `Connection refused` errors

**Solution:**
```bash
# Check MCP server
claude --version

# Restart MCP server
claude restart

# Check logs
cat ~/.claude/logs/mcp-server.log
```

### Problem: MCP Rate Limiting

**Symptoms:**
- `429 Too Many Requests`
- Intermittent failures

**Solution:**
```bash
# Check rate limit status
claude mcp__atlassian__getRateLimitStatus

# Enable rate limiting
export CCPM_RATE_LIMIT_DELAY=1000  # 1 second between requests

# Use exponential backoff
export CCPM_ENABLE_BACKOFF=true
```

---

## Data Consistency Issues

### Problem: Duplicate Issues Created

**Symptoms:**
- Same issue appears multiple times
- Duplicate Jira tickets

**Solution:**
```bash
# Find duplicates
/pm:validate --check-duplicates

# Merge duplicates
/pm:issue-merge 1234 1235

# Prevent future duplicates
export CCPM_DUPLICATE_CHECK=strict
```

### Problem: Missing Issue Links

**Symptoms:**
- GitHub issues not linked to Jira
- Broken cross-references

**Solution:**
```bash
# Find unlinked issues
/pm:validate --find-unlinked

# Batch link issues
/pm:import --link-existing

# Manual link
/pm:issue-link 1234 PROJ-567
```

---

## Common Error Messages

### "Cloud ID not found"
```bash
# Solution
claude mcp__atlassian__getAccessibleAtlassianResources
# Copy the cloud ID to settings.local.json
```

### "Transition not available"
```bash
# List available transitions
/pm:issue-transitions 1234

# Update transition mapping in config
```

### "Field required but not provided"
```bash
# Check required fields
/pm:search --show-required-fields

# Add missing fields to config
```

### "GitHub rate limit exceeded"
```bash
# Check rate limit
gh api rate_limit

# Use authentication token
export GITHUB_TOKEN="your-token"
```

---

## Recovery Procedures

### Full System Recovery

1. **Backup Current State**
```bash
tar -czf ccpm-backup.tar.gz .claude/ claude/settings.local.json
```

2. **Reset System**
```bash
# Clear all caches
rm -rf ~/.cache/ccpm-jira/

# Reset configuration
rm claude/settings.local.json

# Re-initialize
/pm:init
```

3. **Restore Data**
```bash
# Import issues
/pm:import --from-backup ccpm-backup.tar.gz

# Re-sync with Jira
/pm:sync --full
```

### Partial Recovery

**Recover Single Epic:**
```bash
# Export epic data
/pm:epic-export user-authentication > epic-backup.json

# Clear epic
rm -rf .claude/epics/user-authentication/

# Re-import
/pm:epic-import epic-backup.json
```

**Recover Search Index:**
```bash
# Rebuild search index
/pm:search --rebuild-index

# Verify
/pm:search --verify-index
```

---

## Debug Mode

Enable comprehensive debugging to diagnose complex issues:

### Environment Variables

```bash
# Enable all debug output
export CCPM_DEBUG=true
export CCPM_LOG_LEVEL=debug

# Debug specific components
export CCPM_DEBUG_SYNC=true
export CCPM_DEBUG_SEARCH=true
export CCPM_DEBUG_MCP=true

# Log to file
export CCPM_LOG_FILE="/tmp/ccpm-debug.log"

# Verbose HTTP requests
export CCPM_HTTP_DEBUG=true
```

### Debug Commands

```bash
# Trace command execution
/pm:trace epic-sync user-authentication

# Dry run mode
/pm:issue-sync 1234 --dry-run

# Explain query routing
/pm:search --explain "my query"

# Show internal state
/pm:debug --show-state
```

### Analyzing Debug Logs

```bash
# Filter errors
grep ERROR /tmp/ccpm-debug.log

# Track API calls
grep "API Request" /tmp/ccpm-debug.log | wc -l

# Find slow operations
grep "Duration:" /tmp/ccpm-debug.log | sort -k2 -n

# Extract stack traces
awk '/ERROR/,/^$/' /tmp/ccpm-debug.log
```

---

## Getting Help

If issues persist after trying these solutions:

1. **Check Logs:**
   - `~/.claude/logs/`
   - `/tmp/ccpm-*.log`

2. **Run Diagnostics:**
   ```bash
   /pm:diagnose --full > diagnostic-report.txt
   ```

3. **Community Support:**
   - GitHub Issues: Report bugs with diagnostic report
   - Discord: Real-time help from community

4. **Emergency Recovery:**
   ```bash
   /pm:init --emergency-recovery
   ```

Remember to always backup your data before attempting major recovery operations.