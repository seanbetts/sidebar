# iOS test crash triage plan

1) Collect failure evidence: extract xcresult crash logs and identify recurring stack patterns.
2) Localize the failure: run failing tests in isolation with stable order, no parallelism.
3) Instrument memory/race diagnostics: ASan/TSan and allocator diagnostics to pinpoint corruption origin.
4) Audit likely unsafe areas: Unsafe/Unmanaged usage, background tasks at init, shared mutable singletons.
5) Apply minimal fixes and add/adjust tests to confirm stability, then re-run CI steps.
