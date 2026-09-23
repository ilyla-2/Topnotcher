# CELE Topnotcher OS — v3.21.17 UI Interaction Resilience

Manual RC2 testing found that multiple sidebar dropdowns, including Practice and Progress, could be unresponsive.

The four sidebar clusters share a common late-bound interaction handler. v3.21.17 adds a narrow CSP-compatible external interaction module with capture-phase delegated handling for all `data-cluster-toggle` controls. This makes Practice, Progress, Sources & AI, and System independent of earlier optional initializer failures. The Focus Tools menu receives the same resilient delegated treatment.

The patch changes only:

- the main HTML to load one external resilience module;
- the public inclusion manifest;
- the runtime manifest;
- one new JavaScript file: `assets/js/53-ui-interaction-resilience-v32117.js`.

The frozen compiler remains byte-identical. Question data, Coverage Engine math, Readiness, Study Next, learner analytics, engineering calculations, and NSCP content are not changed.

RC3 must pass a real Microsoft Edge click regression across all sidebar clusters before Windows/Tauri packaging can proceed.
