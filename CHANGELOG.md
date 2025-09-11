# Changelog

All notable changes to Claude Code PM will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2025-01-11

### Added

#### Jira Integration
- **Full bidirectional sync** between GitHub Issues and Jira
  - Automatic issue creation and linking
  - Status synchronization across both systems
  - Comment mirroring for complete transparency
- **Natural language search** with intelligent routing
  - `pm:search` automatically searches both GitHub and Jira
  - JQL support when specific syntax is needed
  - Unified results from multiple sources
- **MCP-powered Jira operations** using Atlassian MCP tools
  - Direct API access for faster operations
  - Better error handling and rate limiting
  - Support for custom fields and transitions
- **Issue lifecycle management**
  - `pm:issue-start` updates Jira status automatically
  - `pm:issue-sync` keeps both systems aligned
  - `pm:issue-close` handles resolution in both platforms
- **Epic management with Jira**
  - `pm:epic-decompose --with-jira` creates Jira stories
  - `pm:epic-sync` maintains epic/story relationships
  - Progress tracking across both systems
- **Sprint and project management**
  - Sprint planning support
  - Story point tracking
  - Custom field mapping

#### Enhanced Search Capabilities
- **Unified search interface** (`pm:search`)
  - Natural language queries
  - JQL support with `--jql` flag
  - CQL support for Confluence with `--cql` flag
  - Saved searches with `--save-as` and `--saved`
- **Smart query routing**
  - Automatically detects query type
  - Routes to appropriate search backend
  - Merges results from multiple sources
- **Multiple output formats**
  - Table (default)
  - JSON (`--format json`)
  - CSV (`--format csv`)
  - Markdown (`--format markdown`)

#### Workflow Improvements
- **`pm:next` command** with Jira awareness
  - Considers sprint priorities
  - Checks Jira blockers
  - Intelligent task recommendation
- **Standalone epic commands**
  - `pm:epic-list` shows all epics with Jira sync status
  - `pm:epic-status` provides detailed progress
  - `pm:epic-show` displays full epic details
- **Better status tracking**
  - `pm:standup` includes Jira activity
  - `pm:status` shows cross-system dashboard
  - `pm:blocked` identifies blockers in both systems

### Changed
- **Search command completely rewritten** to support multiple backends
- **Issue commands enhanced** with Jira integration when enabled
- **Epic workflow streamlined** with parallel GitHub/Jira operations
- **Configuration moved to** `claude/settings.local.json` for better security

### Improved
- **Error handling** with graceful fallbacks when Jira is unavailable
- **Performance** through MCP integration and better caching
- **Documentation** with comprehensive examples and troubleshooting
- **Validation** with cross-system integrity checks

### Fixed
- Search timeout issues with large repositories
- Status synchronization edge cases
- Epic progress calculation accuracy
- Branch naming for Jira integration

## [1.5.0] - 2024-12-15

### Added
- Git worktree support for parallel development
- Specialized agents for different task types
- Context preservation system
- Automatic progress tracking

### Changed
- Improved task decomposition algorithm
- Better conflict detection for parallel work
- Enhanced GitHub integration

### Fixed
- Context loss between sessions
- Merge conflicts in parallel development
- Task dependency resolution

## [1.0.0] - 2024-11-01

### Added
- Initial release
- PRD creation and parsing
- Epic decomposition
- GitHub Issues integration
- Basic PM commands
- Command reference documentation

[2.0.0]: https://github.com/automazeio/ccpm/compare/v1.5.0...v2.0.0
[1.5.0]: https://github.com/automazeio/ccpm/compare/v1.0.0...v1.5.0
[1.0.0]: https://github.com/automazeio/ccpm/releases/tag/v1.0.0