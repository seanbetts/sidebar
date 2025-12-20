# folder-config

Centralized folder structure management for Agent Smith documents. Provides folder aliases, path resolution, and navigation tools.

## Description

Manages the folder structure within `~/Documents/Agent Smith/Documents/` by maintaining a configuration of folder aliases. This enables shorter, semantic paths (e.g., `@notes` instead of `Notes/`) and makes it easier for both users and other skills to reference document locations.

## When to Use

- **Setup**: Run `init_config.py` once to scan your existing folder structure and create initial configuration
- **Navigation**: Use `browse.py` to explore your folder hierarchy
- **Path Resolution**: Other skills use `get_folder.py` internally to resolve `@alias` paths
- **Custom Aliases**: Use `set_alias.py` to create shortcuts for frequently accessed folders
- **List Aliases**: Use `list_folders.py` to see all available folder shortcuts

## Scripts

### init_config.py
Scans the Documents folder and creates an initial configuration with automatic aliases.

```bash
python init_config.py [--json]
```

**Output**: Creates `~/.agent-smith/folder_config.yaml` with discovered folders and suggested aliases.

### get_folder.py
Resolves a folder alias to its full path. Used internally by other skills.

```bash
python get_folder.py ALIAS [--json]
```

**Arguments**:
- `ALIAS`: Folder alias (with or without `@` prefix)

**Example**:
```bash
python get_folder.py @notes
# Returns: Notes
python get_folder.py coding
# Returns: Personal/Coding
```

### list_folders.py
Lists all configured folder aliases and their paths.

```bash
python list_folders.py [--json]
```

**Output**: Table or JSON of all aliases and their corresponding paths.

### set_alias.py
Creates or updates a folder alias.

```bash
python set_alias.py ALIAS PATH [--json]
```

**Arguments**:
- `ALIAS`: Alias name (without `@` prefix)
- `PATH`: Relative path from Documents folder

**Example**:
```bash
python set_alias.py quick-notes Notes/Quick
# Creates @quick-notes → Notes/Quick
```

### browse.py
Interactive folder tree view of the Documents structure.

```bash
python browse.py [--path PATH] [--depth DEPTH] [--json]
```

**Arguments**:
- `--path`: Starting path (default: root)
- `--depth`: Maximum depth to display (default: 3)

## Configuration

Configuration is stored in `~/.agent-smith/folder_config.yaml`:

```yaml
base_path: ~/Documents/Agent Smith/Documents
aliases:
  archive: Archive
  notes: Notes
  personal: Personal
  work: Work
  coding: Personal/Coding
  ideas: Personal/Ideas
  health: Personal/Health
  writing: Personal/Writing
  # ... more aliases
```

## Integration with Other Skills

Other skills (local-write, local-read, local-search, local-manage) support `@alias` syntax:

```bash
# Using aliases
python create_file.py "@notes/my-note.md"
python list_files.py @work
python search_files.py --name "*.md" --extension md @writing

# Without aliases (still works)
python create_file.py "Notes/my-note.md"
```

## Future Skills

This system enables domain-specific skills that know where to save files:
- **notes skill**: Automatically saves to `@notes`
- **web-save skill**: Saves articles to `@articles` (configurable)
- **journal skill**: Saves daily entries to `@journal`

Each skill can define its default folder in its own configuration while leveraging the centralized alias system.
