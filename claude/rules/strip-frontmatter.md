# Strip Frontmatter

Standard approach for removing YAML frontmatter before sending content to Jira.

## The Problem

YAML frontmatter contains internal metadata that should not appear in Jira issues:
- status, created, updated fields
- Internal references and IDs
- Local file paths

## The Solution

Use sed to strip frontmatter from any markdown file:

```bash
# Strip frontmatter (everything between first two --- lines)
sed '1,/^---$/d; 1,/^---$/d' input.md > output.md
```

This removes:
1. The opening `---` line
2. All YAML content
3. The closing `---` line

## When to Strip Frontmatter

Always strip frontmatter when:
- Creating Jira issues from markdown files
- Posting file content as comments
- Displaying content to external users
- Syncing to any external system

## Examples

### Creating an issue from a file
```bash
# Bad - includes frontmatter
# Sending raw file content to Jira

# Good - strips frontmatter
sed '1,/^---$/d; 1,/^---$/d' task.md > /tmp/clean.md
# Use cleaned content for Jira issue description
```

### Posting a comment
```bash
# Strip frontmatter before posting
sed '1,/^---$/d; 1,/^---$/d' progress.md > /tmp/comment.md
# Use cleaned content for Jira comment via MCP
```

### In a loop
```bash
for file in *.md; do
  # Strip frontmatter from each file
  sed '1,/^---$/d; 1,/^---$/d' "$file" > "/tmp/$(basename $file)"
  # Use the clean version
done
```

## Alternative Approaches

If sed is not available or you need more control:

```bash
# Using awk
awk 'BEGIN{fm=0} /^---$/{fm++; next} fm==2{print}' input.md > output.md

# Using grep with line numbers
grep -n "^---$" input.md | head -2 | tail -1 | cut -d: -f1 | xargs -I {} tail -n +$(({}+1)) input.md
```

## Important Notes

- Always test with a sample file first
- Keep original files intact
- Use temporary files for cleaned content
- Some files may not have frontmatter - the command handles this gracefully