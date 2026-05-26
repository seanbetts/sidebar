# Apple Static Source Guards

Most Apple tests should assert behavior through public APIs, view models, reducers, parsers, or
rendered views. Static source guards are reserved for architectural constraints that cannot be
expressed reliably at runtime, such as deleted-file guards, target-membership contracts, generated
asset usage, or deliberate source-level dependency boundaries.

When a static source guard is still the right tool, use
`ios/sideBar/sideBarTests/StaticSourceGuard.swift` instead of ad hoc file-path resolution and
string loading. Keep each assertion narrow:

- Read only the smallest source file set needed for the invariant.
- Prefer positive API or behavior assertions when the production code exposes a stable seam.
- Normalize whitespace through the helper before matching source snippets.
- Keep broad source sweeps in dedicated `*SourceTests.swift` files so they are easy to audit.
- Move a guard back to a behavioral test when the production code grows a suitable API.

Source guards are not a substitute for runtime coverage. They are a documented static-lint lane
inside the existing XCTest target for constraints that otherwise regress silently.
