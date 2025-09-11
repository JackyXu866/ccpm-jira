# Configuration Reference

This comprehensive guide covers all configuration options for Claude Code PM with Jira integration. Each setting is explained with examples, defaults, and use cases.

## Table of Contents

- [Configuration Overview](#configuration-overview)
- [Configuration Files](#configuration-files)
- [Environment Variables](#environment-variables)
- [Core Settings](#core-settings)
- [Jira Configuration](#jira-configuration)
- [GitHub Configuration](#github-configuration)
- [Search Configuration](#search-configuration)
- [Cache Configuration](#cache-configuration)
- [Performance Settings](#performance-settings)
- [Security Settings](#security-settings)
- [Advanced Settings](#advanced-settings)
- [Migration Guide](#migration-guide)

---

## Configuration Overview

Claude Code PM uses a layered configuration system:

1. **Default Configuration** - Built-in defaults
2. **Global Configuration** - User-level settings (`~/.config/ccpm-jira/`)
3. **Project Configuration** - Project-specific (`claude/settings.local.json`)
4. **Environment Variables** - Runtime overrides
5. **Command Arguments** - Per-command overrides

### Configuration Precedence

```
Command Args > Environment > Project > Global > Defaults
```

### Configuration Structure

```json
{
  "version": "2.0",
  "core": { /* Core settings */ },
  "jira": { /* Jira integration */ },
  "github": { /* GitHub settings */ },
  "search": { /* Search configuration */ },
  "cache": { /* Cache settings */ },
  "performance": { /* Performance tuning */ },
  "security": { /* Security options */ },
  "advanced": { /* Advanced features */ }
}
```

---

## Configuration Files

### Project Configuration (`claude/settings.local.json`)

Primary configuration file for project-specific settings:

```json
{
  "version": "2.0",
  "jira": {
    "enabled": true,
    "project_key": "PROJ",
    "site_url": "https://company.atlassian.net",
    "cloud_id": "12345-6789-abcd-ef01",
    "default_assignee": "current_user"
  }
}
```

### Global Configuration (`~/.config/ccpm-jira/config.json`)

User-level defaults applied to all projects:

```json
{
  "user": {
    "name": "John Doe",
    "email": "john.doe@company.com",
    "default_role": "developer"
  },
  "preferences": {
    "editor": "vim",
    "theme": "dark",
    "notifications": true
  }
}
```

### Permissions Configuration (`claude/settings.local.json`)

Controls Claude Code access permissions:

```json
{
  "permissions": {
    "allow": [
      "Bash(git *)",
      "Bash(gh *)",
      "WebSearch",
      "WebFetch(domain:github.com)",
      "mcp__atlassian__*"
    ],
    "deny": [
      "Bash(rm -rf /)",
      "Bash(sudo *)"
    ]
  }
}
```

---

## Environment Variables

### Core Environment Variables

```bash
# API Authentication
export JIRA_API_TOKEN="your-api-token"
export JIRA_USER_EMAIL="your.email@company.com"
export JIRA_SITE_URL="https://company.atlassian.net"
export GITHUB_TOKEN="ghp_xxxxxxxxxxxx"

# Runtime Configuration
export CCPM_CONFIG_PATH="/custom/path/to/config"
export CCPM_CACHE_DIR="/custom/cache/directory"
export CCPM_DEBUG=true
export CCPM_LOG_LEVEL=debug

# Performance Tuning
export CCPM_MAX_PARALLEL_JOBS=4
export CCPM_REQUEST_TIMEOUT=30
export CCPM_CACHE_TTL=300
export CCPM_BATCH_SIZE=10
```

### Feature Flags

```bash
# Enable experimental features
export CCPM_ENABLE_EXPERIMENTS=true
export CCPM_FEATURE_BULK_SYNC=true
export CCPM_FEATURE_AI_ASSIST=true
export CCPM_FEATURE_WEBHOOKS=false

# Disable features
export CCPM_DISABLE_CACHE=false
export CCPM_DISABLE_ANIMATIONS=false
```

### Debug Variables

```bash
# Debug specific components
export CCPM_DEBUG_SYNC=true
export CCPM_DEBUG_SEARCH=true
export CCPM_DEBUG_MCP=true
export CCPM_DEBUG_CACHE=true

# Performance profiling
export CCPM_PROFILE=true
export CCPM_TIMING=true
export CCPM_MEMORY_STATS=true
```

---

## Core Settings

### Basic Configuration

```json
{
  "core": {
    "version": "2.0",
    "project_name": "My Project",
    "default_epic_dir": ".claude/epics",
    "default_prd_dir": ".claude/prds",
    "date_format": "YYYY-MM-DD",
    "time_format": "HH:mm:ss",
    "timezone": "UTC",
    "locale": "en-US"
  }
}
```

### Workflow Settings

```json
{
  "core": {
    "workflow": {
      "auto_sync": true,
      "sync_interval": 300,
      "conflict_resolution": "prompt",
      "branch_naming": "jira",
      "commit_format": "conventional",
      "pr_template": "default"
    }
  }
}
```

### File Management

```json
{
  "core": {
    "files": {
      "task_extension": ".md",
      "backup_enabled": true,
      "backup_count": 5,
      "archive_completed": true,
      "archive_after_days": 30
    }
  }
}
```

---

## Jira Configuration

### Basic Jira Setup

```json
{
  "jira": {
    "enabled": true,
    "site_url": "https://company.atlassian.net",
    "cloud_id": "12345-6789-abcd-ef01",
    "project_key": "PROJ",
    "api_version": "3"
  }
}
```

### Authentication Options

```json
{
  "jira": {
    "auth": {
      "method": "api_token",
      "token_env_var": "JIRA_API_TOKEN",
      "user_email_env_var": "JIRA_USER_EMAIL",
      "oauth": {
        "enabled": false,
        "client_id": "",
        "redirect_uri": ""
      }
    }
  }
}
```

### Issue Type Configuration

```json
{
  "jira": {
    "issue_types": {
      "epic": {
        "name": "Epic",
        "id": "10000"
      },
      "story": {
        "name": "Story",
        "id": "10001",
        "default_for_tasks": true
      },
      "task": {
        "name": "Task",
        "id": "10002"
      },
      "bug": {
        "name": "Bug",
        "id": "10003"
      },
      "subtask": {
        "name": "Sub-task",
        "id": "10004"
      }
    }
  }
}
```

### Custom Field Mappings

```json
{
  "jira": {
    "custom_fields": {
      "story_points": {
        "id": "customfield_10001",
        "type": "number",
        "default": 3
      },
      "github_url": {
        "id": "customfield_10100",
        "type": "string",
        "auto_populate": true
      },
      "acceptance_criteria": {
        "id": "customfield_10002",
        "type": "text",
        "from_task_file": true
      },
      "epic_link": {
        "id": "customfield_10005",
        "type": "epic_link"
      },
      "sprint": {
        "id": "customfield_10006",
        "type": "sprint",
        "use_active": true
      },
      "team": {
        "id": "customfield_10007",
        "type": "select",
        "default": "Backend"
      }
    }
  }
}
```

### Workflow Transitions

```json
{
  "jira": {
    "transitions": {
      "start": {
        "name": "Start Progress",
        "id": "21",
        "from_statuses": ["To Do", "Open"]
      },
      "done": {
        "name": "Done",
        "id": "31",
        "resolutions": ["Fixed", "Done"]
      },
      "wont_do": {
        "name": "Won't Do",
        "id": "41",
        "resolutions": ["Won't Do", "Duplicate"]
      },
      "review": {
        "name": "In Review",
        "id": "51"
      },
      "blocked": {
        "name": "Blocked",
        "id": "61"
      }
    }
  }
}
```

### Default Values

```json
{
  "jira": {
    "defaults": {
      "priority": "Medium",
      "components": ["Backend"],
      "labels": ["ccpm-managed"],
      "fix_versions": ["current_sprint"],
      "assignee": "current_user",
      "reporter": "current_user"
    }
  }
}
```

### Advanced Jira Settings

```json
{
  "jira": {
    "advanced": {
      "bulk_operations": true,
      "max_batch_size": 50,
      "rate_limit_delay": 100,
      "retry_attempts": 3,
      "retry_delay": 1000,
      "timeout": 30000,
      "validate_fields": true,
      "auto_link_pull_requests": true,
      "sync_comments": true,
      "sync_attachments": false,
      "webhook_enabled": false,
      "webhook_url": ""
    }
  }
}
```

---

## GitHub Configuration

### Basic GitHub Settings

```json
{
  "github": {
    "enabled": true,
    "owner": "company",
    "repo": "project",
    "default_branch": "main",
    "api_version": "v3"
  }
}
```

### Issue Templates

```json
{
  "github": {
    "templates": {
      "epic": {
        "labels": ["epic", "enhancement"],
        "milestone": "current",
        "projects": ["Product Roadmap"]
      },
      "task": {
        "labels": ["task"],
        "assignees": ["@me"]
      },
      "bug": {
        "labels": ["bug"],
        "template": ".github/ISSUE_TEMPLATE/bug_report.md"
      }
    }
  }
}
```

### Pull Request Settings

```json
{
  "github": {
    "pull_requests": {
      "template": ".github/pull_request_template.md",
      "auto_assign": true,
      "reviewers": ["team-leads"],
      "draft_by_default": false,
      "delete_branch_on_merge": true,
      "squash_merge": true
    }
  }
}
```

---

## Search Configuration

### Search Engine Settings

```json
{
  "search": {
    "default_engine": "hybrid",
    "engines": {
      "natural_language": {
        "enabled": true,
        "provider": "mcp_atlassian",
        "confidence_threshold": 0.7
      },
      "jql": {
        "enabled": true,
        "syntax_validation": true,
        "auto_correct": true
      },
      "hybrid": {
        "enabled": true,
        "nl_weight": 0.6,
        "jql_weight": 0.4
      }
    }
  }
}
```

### Search Defaults

```json
{
  "search": {
    "defaults": {
      "max_results": 25,
      "include_archived": false,
      "include_subtasks": false,
      "sort_by": "relevance",
      "highlight_matches": true
    }
  }
}
```

### Saved Searches

```json
{
  "search": {
    "saved_searches": {
      "my_open": {
        "query": "assignee = currentUser() AND status not in (Done, Closed)",
        "type": "jql"
      },
      "high_priority": {
        "query": "priority in (High, Critical) AND project = PROJ",
        "type": "jql"
      },
      "recent_updates": {
        "query": "updated >= -7d",
        "type": "jql"
      },
      "my_reviews": {
        "query": "reviewer:@me is:open",
        "type": "github"
      }
    }
  }
}
```

### Query Router Configuration

```json
{
  "search": {
    "router": {
      "jql_keywords": ["assignee", "status", "priority", "project"],
      "jql_operators": ["=", "!=", "~", "in", "not in"],
      "confidence_thresholds": {
        "jql": 6,
        "hybrid": 3,
        "nl": 0
      }
    }
  }
}
```

---

## Cache Configuration

### Cache Settings

```json
{
  "cache": {
    "enabled": true,
    "directory": "~/.cache/ccpm-jira",
    "max_size_mb": 100,
    "eviction_policy": "lru",
    "compression": true
  }
}
```

### Cache TTL by Type

```json
{
  "cache": {
    "ttl": {
      "search_results": 300,
      "user_info": 3600,
      "project_metadata": 86400,
      "issue_details": 600,
      "transitions": 1800,
      "custom_fields": 86400
    }
  }
}
```

### Cache Strategies

```json
{
  "cache": {
    "strategies": {
      "search": {
        "enabled": true,
        "max_entries": 1000,
        "ttl": 300,
        "key_normalization": true
      },
      "api_responses": {
        "enabled": true,
        "selective": true,
        "exclude_patterns": ["/auth/*", "/webhooks/*"]
      }
    }
  }
}
```

---

## Performance Settings

### Concurrency Control

```json
{
  "performance": {
    "concurrency": {
      "max_parallel_requests": 4,
      "max_parallel_syncs": 2,
      "queue_size": 100,
      "worker_threads": 4
    }
  }
}
```

### Rate Limiting

```json
{
  "performance": {
    "rate_limiting": {
      "enabled": true,
      "requests_per_minute": 60,
      "burst_size": 10,
      "backoff_strategy": "exponential",
      "max_retries": 3
    }
  }
}
```

### Optimization Settings

```json
{
  "performance": {
    "optimizations": {
      "batch_operations": true,
      "lazy_loading": true,
      "delta_sync": true,
      "request_pooling": true,
      "connection_reuse": true
    }
  }
}
```

### Resource Limits

```json
{
  "performance": {
    "limits": {
      "max_memory_mb": 512,
      "max_cache_mb": 100,
      "max_log_size_mb": 50,
      "max_response_size_mb": 10,
      "timeout_seconds": 30
    }
  }
}
```

---

## Security Settings

### Authentication Security

```json
{
  "security": {
    "authentication": {
      "token_storage": "keychain",
      "token_encryption": true,
      "session_timeout": 3600,
      "mfa_required": false
    }
  }
}
```

### API Security

```json
{
  "security": {
    "api": {
      "ssl_verify": true,
      "min_tls_version": "1.2",
      "certificate_pinning": false,
      "proxy": {
        "enabled": false,
        "host": "",
        "port": 8080,
        "auth_required": false
      }
    }
  }
}
```

### Data Protection

```json
{
  "security": {
    "data": {
      "encrypt_cache": false,
      "encrypt_logs": false,
      "sanitize_outputs": true,
      "mask_sensitive_data": true,
      "audit_logging": true
    }
  }
}
```

---

## Advanced Settings

### Experimental Features

```json
{
  "advanced": {
    "experimental": {
      "ai_assist": false,
      "smart_conflict_resolution": false,
      "predictive_caching": false,
      "auto_epic_decomposition": false,
      "natural_language_commands": false
    }
  }
}
```

### Plugin System

```json
{
  "advanced": {
    "plugins": {
      "enabled": true,
      "directory": "~/.config/ccpm-jira/plugins",
      "auto_load": true,
      "allowed_hooks": [
        "pre_command",
        "post_command",
        "pre_sync",
        "post_sync"
      ]
    }
  }
}
```

### Webhook Configuration

```json
{
  "advanced": {
    "webhooks": {
      "enabled": false,
      "endpoints": {
        "jira": "https://api.example.com/webhooks/jira",
        "github": "https://api.example.com/webhooks/github"
      },
      "events": [
        "issue.created",
        "issue.updated",
        "issue.transitioned"
      ],
      "secret": "webhook-secret-key"
    }
  }
}
```

### Debug Configuration

```json
{
  "advanced": {
    "debug": {
      "enabled": false,
      "log_level": "info",
      "log_file": "/tmp/ccpm-debug.log",
      "include_timestamps": true,
      "include_stack_traces": false,
      "components": ["sync", "search", "mcp"]
    }
  }
}
```

---

## Migration Guide

### Migrating from v1.x to v2.0

1. **Backup Current Configuration**
   ```bash
   cp claude/settings.local.json claude/settings.v1.backup.json
   ```

2. **Update Configuration Structure**
   ```bash
   # Old v1.x structure
   {
     "jira_enabled": true,
     "jira_project": "PROJ"
   }
   
   # New v2.0 structure
   {
     "version": "2.0",
     "jira": {
       "enabled": true,
       "project_key": "PROJ"
     }
   }
   ```

3. **Migrate Custom Fields**
   ```bash
   # Run migration tool
   /pm:migrate-config --from v1 --to v2
   ```

4. **Update Environment Variables**
   ```bash
   # Old
   export CCPM_JIRA_TOKEN="..."
   
   # New
   export JIRA_API_TOKEN="..."
   ```

### Configuration Validation

```bash
# Validate configuration
/pm:validate-config

# Check for deprecations
/pm:config --check-deprecations

# Generate default config
/pm:config --generate-default > claude/settings.local.json
```

### Troubleshooting Configuration Issues

1. **Invalid JSON**
   ```bash
   # Validate and fix JSON
   jq '.' claude/settings.local.json
   ```

2. **Missing Required Fields**
   ```bash
   # Show required fields
   /pm:config --show-required
   ```

3. **Reset to Defaults**
   ```bash
   # Reset configuration
   /pm:init --reset-config
   ```

---

## Best Practices

### Configuration Management

1. **Use Environment Variables for Secrets**
   - Never commit API tokens to version control
   - Use `.env` files with `.gitignore`

2. **Layer Configurations Appropriately**
   - Global: User preferences
   - Project: Team settings
   - Environment: Deployment-specific

3. **Document Custom Settings**
   - Add comments in configuration files
   - Maintain a team wiki for custom fields

4. **Regular Backups**
   ```bash
   # Backup script
   cp claude/settings.local.json "backups/settings-$(date +%Y%m%d).json"
   ```

5. **Version Control Considerations**
   ```gitignore
   # .gitignore
   claude/settings.local.json
   .env
   *.secret
   ```

### Performance Tuning

1. **Start with Defaults**
   - Only tune when needed
   - Measure before and after

2. **Cache Optimization**
   - Monitor cache hit rates
   - Adjust TTL based on usage patterns

3. **API Rate Limits**
   - Respect provider limits
   - Use exponential backoff

4. **Batch Operations**
   - Group related operations
   - Use bulk endpoints when available

Remember: Configuration is powerful but complexity has a cost. Start simple and add complexity only when needed.