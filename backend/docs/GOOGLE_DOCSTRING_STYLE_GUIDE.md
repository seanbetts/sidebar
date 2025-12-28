# Google-Style Docstring Guide for sideBar

This guide provides examples and templates for writing Google-style docstrings in the sideBar backend.

---

## Why Google Style?

- **Clean and readable**: Easy to scan and understand
- **Well-supported**: VS Code, Sphinx, and other tools recognize it
- **Clear sections**: Args, Returns, Raises are clearly separated
- **Standard**: Widely adopted in Python community

---

## Configuration

### Tools Installed

We use three tools to enforce Google-style docstrings:

1. **interrogate** - Measures docstring coverage
2. **pydocstyle** - Checks docstring style compliance
3. **darglint** - Validates docstrings match function signatures

### Configuration Files

- `.pydocstyle` - Pydocstyle configuration
- `pyproject.toml` - Contains `[tool.interrogate]` and `[tool.pydocstyle]` sections

### Quick Commands

```bash
# Check docstring coverage
interrogate -v api/

# Check docstring style
pydocstyle api/

# Validate docstrings match signatures
darglint -v 2 api/

# Check specific file
pydocstyle api/routers/notes.py
```

---

## Basic Structure

```python
def function_name(param1: str, param2: int = 0) -> dict:
    """Short one-line summary (ends with period).

    Optional longer description explaining what this function does,
    any important context, and how it relates to the broader system.
    Can span multiple lines.

    Args:
        param1: Description of param1. Explain constraints, format,
            and valid values.
        param2: Description of param2. Explain default behavior.
            Defaults to 0.

    Returns:
        Dictionary containing:
            - key1 (str): Description of key1
            - key2 (int): Description of key2

        Or for simple returns:
        True if successful, False otherwise.

    Raises:
        ValueError: When param1 is empty or invalid
        HTTPException: When validation fails (status 400)

    Example:
        >>> result = function_name("test", 42)
        >>> print(result['key1'])
        'value'

    Note:
        Any additional notes, warnings, or caveats.
    """
```

---

## Module Docstrings

Every `.py` file should start with a module docstring:

```python
"""Brief description of what this module provides.

Longer description if needed. Explain the module's role in the system,
what components it contains, and how it should be used.
"""
from __future__ import annotations
# ... imports
```

**Current state**: ✅ 100% coverage - all modules have docstrings

---

## Class Docstrings

```python
class NotesService:
    """Service layer for notes operations.

    Handles all business logic related to notes including creation,
    retrieval, updating, deletion, and organization. Interacts with
    the database through SQLAlchemy ORM.

    Attributes:
        H1_PATTERN: Regex pattern for matching markdown H1 headers

    Example:
        >>> service = NotesService()
        >>> note = service.create_note(db, user_id, content="# Hello")
    """

    H1_PATTERN = re.compile(r"^#\s+(.+)$", re.MULTILINE)

    # ... methods
```

**Current state**: ⚠️ 63% coverage - 15 classes missing docstrings

---

## Function and Method Docstrings

### Simple Function (No Args)

```python
def get_all_notes() -> list[Note]:
    """Get all notes from the database.

    Returns:
        List of Note objects ordered by creation date.
    """
```

### Function with Arguments

```python
def create_note(
    db: Session,
    user_id: str,
    content: str,
    metadata: dict | None = None
) -> Note:
    """Create a new note in the database.

    Extracts title from content H1 header if present, otherwise uses
    "Untitled". Validates user exists and folder path is valid.

    Args:
        db: Database session for transaction
        user_id: UUID of the current user
        content: Markdown content for the note
        metadata: Optional metadata containing:
            - folder (str): Folder path like "Work/Projects"
            - pinned (bool): Whether note is pinned

    Returns:
        Newly created Note object with ID populated.

    Raises:
        ValueError: If user_id is invalid or content is empty
        HTTPException: If folder path contains invalid characters (400)

    Example:
        >>> note = create_note(
        ...     db,
        ...     "user-uuid",
        ...     "# My Note\n\nContent here",
        ...     {"folder": "Personal"}
        ... )
        >>> print(note.id)
        'note-uuid-here'
    """
```

### Async Function

```python
async def stream_chat(
    request: Request,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id)
) -> StreamingResponse:
    """Stream chat response with tool calls via SSE.

    Processes user message, executes Claude streaming with tool support,
    and returns server-sent events (SSE) stream.

    Args:
        request: FastAPI request containing JSON body with:
            - message (str): User's chat message
            - conversation_id (str, optional): Existing conversation UUID
            - history (list, optional): Previous message history
        db: Database session dependency
        user_id: Current authenticated user ID dependency

    Returns:
        StreamingResponse with SSE events:
            - token: Text content chunks
            - tool_call: Tool execution started
            - tool_result: Tool execution completed
            - complete: Stream finished
            - error: Error occurred

    Raises:
        HTTPException: 401 if user not authenticated
        HTTPException: 400 if message is empty

    Note:
        Maintains conversation context automatically. Creates new
        conversation if conversation_id not provided.
    """
```

### API Router Endpoint

```python
@router.get("/notes/{note_id}")
async def get_note(
    note_id: str,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token)
) -> dict:
    """Get a single note by ID.

    Retrieves note content and metadata. Returns 404 if note doesn't
    exist or doesn't belong to current user.

    Path Parameters:
        note_id: UUID of the note to retrieve

    Args:
        note_id: Note UUID from path parameter
        db: Database session dependency
        user_id: Current user ID from authentication
        _: Bearer token validation (ensures authenticated)

    Returns:
        Dictionary with note data:
            {
                "id": "uuid",
                "title": "Note Title",
                "content": "# Title\n\nContent...",
                "created_at": "2024-01-01T00:00:00Z",
                "updated_at": "2024-01-01T00:00:00Z",
                "metadata": {
                    "folder": "Work",
                    "pinned": false,
                    "archived": false
                }
            }

    Raises:
        HTTPException: 404 if note not found or access denied
        HTTPException: 401 if not authenticated

    Example:
        GET /api/notes/123e4567-e89b-12d3-a456-426614174000
        Authorization: Bearer <token>

        Response:
        {
            "id": "123e4567-e89b-12d3-a456-426614174000",
            "title": "My Note",
            ...
        }
    """
```

### Tool Parameter Mapping Function

```python
def build_note_create_args(
    db: Session,
    user_id: str,
    content: str | None = None,
    title: str | None = None,
    folder: str | None = None
) -> dict:
    """Map LLM tool call parameters to NotesService.create_note() arguments.

    Transforms and validates parameters from Claude's tool call format
    into the format expected by NotesService. Derives title from H1
    header in content if not explicitly provided.

    Args:
        db: Database session for folder validation
        user_id: Current user ID for scoping
        content: Markdown content (optional, uses template if None)
        title: Note title (optional, derived from content H1 if None)
        folder: Folder path like "Work/Projects" (optional, root if None)

    Returns:
        Dictionary with validated arguments for NotesService.create_note():
            {
                'user_id': str,
                'content': str,
                'metadata': {
                    'folder': str,
                    'title': str
                }
            }

    Raises:
        ValueError: If both content and title are empty/None

    Example:
        >>> args = build_note_create_args(
        ...     db,
        ...     "user-123",
        ...     content="# Meeting Notes\n\nDiscussed...",
        ...     folder="Work"
        ... )
        >>> print(args['metadata']['title'])
        'Meeting Notes'
    """
```

### Service Method

```python
@staticmethod
def extract_title(content: str, fallback: str) -> str:
    """Extract title from markdown H1 header or use fallback.

    Searches for the first H1 header (# Title) in the markdown content.
    If found, returns the header text. Otherwise returns the fallback.

    Args:
        content: Markdown content to search
        fallback: Default title if no H1 found (e.g., "Untitled")

    Returns:
        Extracted title string or fallback value.

    Example:
        >>> extract_title("# Hello World\n\nContent", "Untitled")
        'Hello World'
        >>> extract_title("No header here", "Untitled")
        'Untitled'
    """
```

---

## Special Cases

### Property Decorator

```python
@property
def is_archived(self) -> bool:
    """Check if note is in archived folder.

    Returns:
        True if note's folder is "Archive" or starts with "Archive/",
        False otherwise.
    """
```

### Static Method

```python
@staticmethod
def normalize_url(url: str) -> str:
    """Normalize URL for consistent storage and comparison.

    Removes trailing slashes, converts to lowercase, and removes
    query parameters and fragments.

    Args:
        url: Raw URL string to normalize

    Returns:
        Normalized URL string.

    Example:
        >>> normalize_url("https://Example.com/Path/?query=1#section")
        'https://example.com/path'
    """
```

### Private Method (Optional)

Private methods (starting with `_`) don't require docstrings, but complex ones benefit from them:

```python
def _validate_path(self, path: str, check_writable: bool) -> Path:
    """Core path validation logic.

    Validates path doesn't escape workspace via traversal or symlinks.
    Optionally checks if path is in writable allowlist.

    Args:
        path: Relative or absolute path to validate
        check_writable: If True, verify path is in writable_paths list

    Returns:
        Resolved absolute Path object within workspace.

    Raises:
        HTTPException: 400 for path traversal or symlink
        HTTPException: 403 for paths outside workspace or not writable
    """
```

---

## Common Patterns in Our Codebase

### Database Session Pattern

```python
def some_operation(
    db: Session,
    user_id: str,
    ...
) -> ReturnType:
    """Operation description.

    Args:
        db: Database session for transaction
        user_id: Current user ID for RLS scoping
        ...

    Returns:
        ...
    """
```

### FastAPI Dependency Injection

```python
async def endpoint(
    param: str,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token)
) -> ResponseType:
    """Endpoint description.

    Args:
        param: Description of path/query parameter
        db: Database session dependency
        user_id: Current user ID from authentication
        _: Bearer token validation (ensures authenticated)

    Returns:
        ...
    """
```

### Tool Execution Pattern

```python
def handle_tool_execution(
    db: Session,
    user_id: str,
    tool_name: str,
    parameters: dict
) -> dict:
    """Execute a tool and return standardized result.

    Args:
        db: Database session
        user_id: Current user ID
        tool_name: Name of tool to execute
        parameters: Tool parameters from LLM

    Returns:
        Standardized result dictionary:
            {
                'success': bool,
                'data': Any | None,
                'error': str | None
            }

    Raises:
        ValueError: If tool_name is unknown
    """
```

---

## Sections Reference

### Required Sections

- **Summary line**: First line, one sentence, ends with period
- **Args**: All parameters (except `self`)
- **Returns**: What the function returns

### Optional Sections

- **Raises**: Exceptions that might be raised
- **Example**: Usage examples (very helpful for complex functions)
- **Note**: Additional context, warnings, or caveats
- **Yields**: For generator functions (instead of Returns)
- **Attributes**: For classes (list class/instance attributes)

### Section Order

1. Summary line
2. Longer description (optional)
3. Args
4. Returns / Yields
5. Raises
6. Example
7. Note / Warning / See Also

---

## VS Code Setup

Install the **autoDocstring** extension for auto-generation:

1. Install extension: `njpwerner.autodocstring`
2. Configure in `.vscode/settings.json`:

```json
{
  "autoDocstring.docstringFormat": "google",
  "autoDocstring.startOnNewLine": true,
  "autoDocstring.includeExtendedSummary": true,
  "autoDocstring.includeName": false,
  "autoDocstring.guessTypes": true
}
```

3. **Usage**: Type `"""` above a function and press Enter

---

## Common Mistakes to Avoid

### ❌ Wrong: Missing types in Args

```python
def create_note(db, user_id, content):
    """Create a note.

    Args:
        db: Database
        user_id: User
        content: Content
    """
```

### ✅ Correct: Descriptive Args

```python
def create_note(db: Session, user_id: str, content: str):
    """Create a new note in the database.

    Args:
        db: SQLAlchemy database session for transaction
        user_id: UUID string of the current authenticated user
        content: Markdown content for the note
    """
```

### ❌ Wrong: Vague Returns

```python
def get_notes():
    """Get notes.

    Returns:
        Notes
    """
```

### ✅ Correct: Specific Returns

```python
def get_notes() -> list[Note]:
    """Get all notes for current user.

    Returns:
        List of Note objects ordered by creation date descending.
        Returns empty list if user has no notes.
    """
```

### ❌ Wrong: Using "Body:" instead of "Args:"

```python
@router.post("/notes")
async def create_note(request: dict):
    """Create a note.

    Body:
        {
            "content": "...",
            "folder": "..."
        }
    """
```

### ✅ Correct: Using Args with request schema

```python
@router.post("/notes")
async def create_note(request: dict):
    """Create a new note.

    Args:
        request: JSON request body containing:
            - content (str): Markdown content
            - folder (str, optional): Folder path

    Returns:
        Created note object with generated ID.
    """
```

---

## Quick Reference Card

```python
def function(arg1: str, arg2: int = 0) -> bool:
    """One-line summary.

    Longer description if needed.

    Args:
        arg1: Description
        arg2: Description. Defaults to 0.

    Returns:
        Description of return value.

    Raises:
        ExceptionType: When this happens

    Example:
        >>> function("test", 42)
        True
    """
```

---

## Checking Your Work

Before committing:

```bash
# 1. Check coverage
interrogate -v api/your_file.py

# 2. Check style
pydocstyle api/your_file.py

# 3. Validate signatures
darglint -v 2 api/your_file.py

# 4. Run all checks
pydocstyle api/ && interrogate -v api/
```

---

## Resources

- [Google Style Guide](https://google.github.io/styleguide/pyguide.html#38-comments-and-docstrings)
- [PEP 257 - Docstring Conventions](https://peps.python.org/pep-0257/)
- [Sphinx Google Style Documentation](https://www.sphinx-doc.org/en/master/usage/extensions/napoleon.html)
- [interrogate Documentation](https://interrogate.readthedocs.io/)
- [pydocstyle Documentation](http://www.pydocstyle.org/)
