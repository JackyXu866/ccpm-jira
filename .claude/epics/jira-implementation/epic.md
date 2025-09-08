---
name: jira-implementation
status: backlog
created: 2025-09-08T15:33:48Z
updated: 2025-09-08T16:14:35Z
progress: 0%
prd: .claude/prds/jira-implementation.md
github: https://github.com/JackyXu866/ccpm-jira/issues/1
---

# Epic: jira-implementation

## Overview
Complete replacement of GitHub Issues with Atlassian Jira using the installed Atlassian MCP. This implementation focuses on minimal code changes while maximizing functionality by leveraging MCP's built-in capabilities for authentication, API operations, and data management.

## Architecture Decisions

### Core Technology Choices
- **Atlassian MCP as primary integration layer** - No custom API wrappers needed
- **Reuse existing CCPM file structure** - Minimal changes to local storage patterns
- **Shell script adaptation** - Replace `gh` CLI calls with MCP tool invocations
- **Maintain Git/GitHub for code operations** - Only issue tracking moves to Jira

### Design Patterns
- **Adapter Pattern** - Create thin wrapper functions that translate existing commands to MCP calls
- **Local Cache Strategy** - Keep existing `.claude/epics/` structure for offline work
- **Command Preservation** - Keep all `/pm:*` commands with same interface

### Key Simplifications
- Use MCP's built-in authentication instead of custom OAuth flows
- Leverage MCP's error handling and rate limiting
- No custom Jira API client needed
- Reuse existing frontmatter format with Jira-specific fields

## Technical Approach

### MCP Integration Layer
- Create `jira-adapter.sh` to centralize all MCP calls
- Map existing GitHub operations to Jira equivalents
- Handle field translations (GitHub labels → Jira components)

### Command Updates
- Update shell scripts to detect and use Jira mode
- Replace `gh` commands with MCP tool invocations
- Maintain backward-compatible command interfaces

### Data Mapping
```
GitHub → Jira Mapping:
- Issue → Story/Task
- Epic (via labels) → Epic (native)
- Milestone → Fix Version
- Labels → Components/Labels
- Assignee → Assignee
- Due date → Due Date (native)
```

### Git Integration
- Branch naming: `PROJ-123-feature-name` format
- PR title format: `[PROJ-123] Feature description`
- Automatic linking via Jira's GitHub integration

## Implementation Strategy

### Incremental Approach
1. Start with read operations (status, list)
2. Add create operations (epic, issue)
3. Implement update operations
4. Add sync and advanced features

### Risk Mitigation
- Test each command in isolation
- Keep GitHub code as fallback during transition
- Implement comprehensive error logging
- Create rollback script if needed

### Testing Approach
- Unit tests for each adapted command
- Integration tests with test Jira project
- End-to-end workflow validation
- Performance benchmarking

## Task Breakdown Preview

High-level tasks (limiting to essential functionality):

- [ ] Task 1: Create MCP integration adapter and authentication setup
- [ ] Task 2: Implement core CRUD operations (create, read, update epics/issues)
- [ ] Task 3: Update init and status commands for Jira
- [ ] Task 4: Migrate epic management commands (sync, decompose, list)
- [ ] Task 5: Update issue workflow commands (start, sync, close)
- [ ] Task 6: Implement Git integration (branch naming, PR linking)
- [ ] Task 7: Add search and query functionality
- [ ] Task 8: Create migration guide and update documentation

## Dependencies

### Required Before Start
- Atlassian MCP properly configured
- Access to test Jira instance
- Jira project with standard issue types

### Runtime Dependencies
- MCP service running
- Network connectivity to Jira
- Git for branch operations

## Success Criteria (Technical)

### Performance Benchmarks
- Issue creation < 2 seconds
- Bulk sync < 10 seconds for 20 issues
- Local cache hit rate > 80%

### Quality Gates
- All existing pm commands work with Jira
- No regression in user workflow
- Error messages clearly indicate Jira-specific issues

### Acceptance Criteria
- Can create epic from PRD
- Can decompose epic to Jira issues
- Can start work on issue with proper branch
- Can sync progress back to Jira
- Git integration creates proper links

## Estimated Effort

### Timeline: 5 days with Claude Code assistance

**Day 1**: MCP adapter and core operations
**Day 2-3**: Command migration (batch updates)
**Day 4**: Git integration and testing
**Day 5**: Documentation and polish

### Critical Path
1. MCP adapter (blocks everything)
2. Core CRUD operations
3. Command updates (can parallelize)
4. Testing and documentation

## Tasks Created
- [ ] #2 - Create MCP integration adapter and authentication setup (parallel: true)
- [ ] #3 - Implement core CRUD operations (parallel: false)
- [ ] #4 - Update init and status commands for Jira (parallel: true)
- [ ] #5 - Migrate epic management commands (parallel: false)
- [ ] #6 - Update issue workflow commands (parallel: true)
- [ ] #7 - Implement Git integration (parallel: true)
- [ ] #8 - Add search and query functionality (parallel: true)
- [ ] #9 - Create migration guide and update documentation (parallel: false)

Total tasks: 8
Parallel tasks: 5
Sequential tasks: 3
Estimated total effort: 50 hours
