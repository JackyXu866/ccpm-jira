---
name: jira-implementation
description: Replace GitHub Issues with Atlassian Jira for enhanced project management capabilities in CCPM workflow
status: backlog
created: 2025-09-08T15:26:12Z
---

# PRD: jira-implementation

## Executive Summary

This PRD outlines the migration of the Claude Code Project Management (CCPM) system from GitHub Issues to Atlassian Jira as the primary work item tracking system. The migration leverages the Atlassian MCP (Model Context Protocol) to provide enhanced project management capabilities including start dates, epics, dependency tracking, and priority management while maintaining GitHub integration for branch creation and pull requests.

## Problem Statement

The current CCPM system is built entirely around GitHub Issues, which has several limitations:

1. **Limited Project Management Features**: GitHub Issues lacks native support for:
   - Start dates and time-based planning
   - True epic hierarchies with proper parent-child relationships
   - Dependency management between tasks
   - Advanced priority schemes
   - Sprint planning and tracking
   - Burndown/burnup charts

2. **Workaround Complexity**: The system currently uses:
   - gh-sub-issue extension for parent-child relationships
   - Custom labels for epic tracking
   - Manual dependency tracking
   - Limited priority options

3. **Enterprise Adoption Barriers**: Many organizations already use Jira as their standard project management tool and need integration rather than parallel systems.

## User Stories

### Primary User: Developer using Claude Code
- **As a developer**, I want to create and manage work items in Jira directly from Claude Code so that I can leverage Jira's advanced features without leaving my development environment
- **As a developer**, I want to maintain the spec-driven development workflow while benefiting from Jira's project management capabilities
- **As a developer**, I want GitHub branches and PRs to automatically link to Jira issues using proper naming conventions

### Secondary User: Project Manager
- **As a project manager**, I want to see all AI-assisted development work in our standard Jira instance so that I can track progress alongside other team work
- **As a project manager**, I want to leverage Jira's reporting and planning tools for AI-assisted development projects
- **As a project manager**, I want to manage dependencies, priorities, and timelines using familiar Jira features

### Tertiary User: Team Lead
- **As a team lead**, I want to coordinate AI and human development work in a single system
- **As a team lead**, I want to use Jira's workflow automation and notification features
- **As a team lead**, I want visibility into parallel AI agent work through Jira's tracking

## Requirements

### Functional Requirements

#### Core Integration
1. **Atlassian MCP Integration**
   - Utilize the installed Atlassian MCP for all Jira operations
   - Support authentication and connection management
   - Handle API rate limits and error recovery

2. **Work Item Management**
   - Create epics in Jira from PRDs
   - Decompose epics into stories/tasks/sub-tasks
   - Update issue status, descriptions, and fields
   - Query and search Jira issues
   - Support custom fields specific to the organization

3. **Field Mapping**
   - Map PRD metadata to Jira epic fields
   - Support Jira-specific fields:
     - Start Date
     - Due Date
     - Epic Link
     - Priority (with custom schemes)
     - Story Points/Time Estimates
     - Components
     - Fix Version/Release
   - Handle dependency links between issues

4. **GitHub Integration**
   - Create branches with Jira issue keys (e.g., `PROJ-123-feature-name`)
   - Update PR titles to include Jira keys
   - Maintain bi-directional linking between Jira and GitHub
   - Post PR status updates to Jira

5. **Command Migration**
   All existing pm commands must be updated:
   - `/pm:init` - Configure Jira connection alongside GitHub
   - `/pm:prd-parse` - Create Jira epic instead of GitHub issue
   - `/pm:epic-sync` - Sync to Jira instead of GitHub
   - `/pm:issue-*` commands - Work with Jira issues
   - `/pm:status` - Pull from Jira APIs

6. **Local Cache**
   - Maintain local file structure for offline work
   - Cache Jira data for performance
   - Handle sync conflicts gracefully

### Non-Functional Requirements

#### Performance
- Issue creation/update < 2 seconds
- Bulk operations for syncing multiple issues
- Efficient caching to minimize API calls
- Support for large projects (1000+ issues)

#### Security
- Secure credential storage for Jira authentication
- Support for OAuth2 and API tokens
- No credentials in code or git history
- Respect Jira permission schemes

#### Scalability
- Handle multiple Jira projects
- Support different Jira configurations (Cloud/Server)
- Work with custom workflows
- Scale to teams of 50+ developers

#### Compatibility
- Work with Jira Cloud and Data Center versions
- Compatible with popular Jira plugins
- Support existing PRDs/epics structure (local files)
- Clean replacement of GitHub Issues functionality

## Success Criteria

1. **Migration Success**
   - 100% of pm commands work with Jira
   - Existing workflows require < 5 minutes of retraining
   - Complete replacement of GitHub Issues with Jira

2. **Performance Metrics**
   - 50% reduction in time spent on project tracking
   - 90% of operations complete in < 3 seconds
   - Zero data loss during sync operations

3. **Adoption Metrics**
   - 80% of team using Jira integration within 2 weeks
   - 95% satisfaction rate with new capabilities
   - 75% reduction in manual Jira updates

4. **Quality Metrics**
   - < 5 bugs per 1000 operations
   - 99.9% sync reliability
   - Zero security incidents

## Constraints & Assumptions

### Constraints
1. Must use Atlassian MCP (already installed)
2. Cannot modify core Jira functionality
3. Must maintain GitHub for code/PR management
4. Limited by Jira API rate limits
5. Must work within existing CCPM file structure

### Assumptions
1. Users have access to Jira instance
2. Jira projects follow standard configurations
3. Atlassian MCP is properly configured
4. Users have necessary Jira permissions
5. GitHub remains the code repository

## Out of Scope

1. **Jira Administration**
   - Creating Jira projects
   - Modifying Jira workflows
   - Managing Jira permissions
   - Jira plugin development

2. **Data Migration**
   - No migration of historical GitHub issues (clean cut-over)
   - No bulk import of existing projects
   - Fresh start with Jira

3. **Advanced Jira Features**
   - Portfolio/Advanced Roadmaps integration
   - Jira Service Management
   - Confluence integration
   - Third-party Jira apps

4. **GitHub Replacement**
   - Moving code repository to Bitbucket
   - Replacing GitHub PRs with Jira PRs
   - GitHub Actions migration

## Dependencies

### External Dependencies
1. **Atlassian MCP** - Must be installed and configured
2. **Jira Instance** - Access to Cloud or Server instance
3. **Jira API** - Stable API endpoints
4. **GitHub API** - For PR/branch creation

### Internal Dependencies
1. **CCPM Core** - Existing command structure
2. **File Structure** - .claude/ directory layout
3. **Agent System** - Parallel execution framework
4. **Context System** - Context preservation mechanism

### Technical Dependencies
1. **Authentication** - Jira OAuth2/tokens
2. **Network** - Stable internet connection
3. **Storage** - Local cache directory
4. **Git** - For branch operations

## Implementation Phases

### Phase 1: Core Integration (Day 1)
- Atlassian MCP connection setup
- Basic CRUD operations for Jira issues
- Authentication management

### Phase 2: Command Migration (Day 2-3)
- Update all pm:* commands
- Implement field mapping
- Local cache system

### Phase 3: GitHub Integration (Day 4)
- Branch naming with Jira keys
- PR-Jira linking
- Status synchronization

### Phase 4: Testing & Refinement (Day 5)
- End-to-end testing
- Performance optimization
- Documentation updates

## Risk Mitigation

1. **API Limits** - Implement intelligent caching and batch operations
2. **Clean Cut-over** - Clear documentation on the switch date
3. **Data Loss** - Local backup of all operations
4. **Performance** - Async operations where possible
5. **Adoption** - Comprehensive migration guide and training