# Plan: Reduce File/Type Length Lint Warnings

## Goals
- Refactor iOS Swift files that exceed SwiftLint file/type length limits.
- Preserve behavior while splitting code into extensions or helper types.

## Steps
1) Identify the largest offenders and map logical groupings to split into extensions or supporting files.
2) Refactor one module at a time, moving cohesive groups of methods into extensions or helper types in the same file (or new files if needed), keeping API stable.
3) Re-run `swiftlint --config .swiftlint.yml` to confirm reduced file/type length warnings and adjust as needed.

## Notes
- Prefer extensions to avoid behavior changes.
- Avoid altering public APIs unless necessary.
