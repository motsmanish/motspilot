# XML Tag Reference — motspilot Phase Prompts

Canonical list of all XML tags used across phase prompts. Phase prompts should reference
tags from this list to prevent drift and typos.

## Structural tags (present in every phase prompt)

| Tag | Purpose | Used in |
|-----|---------|---------|
| `<hard_constraints>` | Non-negotiable rules at the top of every prompt | All 5 phases |
| `<analysis>` | Scratch work / thinking space (not forwarded to downstream phases) | All 5 phases |
| `<summary>` | Clean deliverable (authoritative output downstream phases read) | All 5 phases |
| `<output_format>` | Output structure specification | All 5 phases |
| `<output_scaling>` | Depth guidance based on feature size (small/medium/large) | Architecture, Development, Delivery |
| `<completion_checklist>` | 12-item numbered checklist with evidence requirements | All 5 phases |
| `<task-notification>` | Structured XML envelope emitted after phase completion | All 5 phases |
| `<task_notification>` | Prompt section instructing subagent to emit `<task-notification>` | All 5 phases |

## Investigation guards (one per phase)

| Tag | Phase |
|-----|-------|
| `<investigate_before_designing>` | Architecture |
| `<investigate_before_coding>` | Development |
| `<investigate_before_testing>` | Testing |
| `<investigate_before_judging>` | Verification |
| `<investigate_before_documenting>` | Delivery |

## Phase-specific tags

### Architecture
| Tag | Purpose |
|-----|---------|
| `<how_you_think>` | Thinking framework |
| `<anti_overengineering>` | Scope creep prevention |
| `<protecting_existing_code>` | Integration safety rules |
| `<decomposition>` | Work breakdown rules for large features (5–30 units) |

### Development
| Tag | Purpose |
|-----|---------|
| `<how_you_work>` | Build order (Foundation → Logic → Interface) |
| `<tool_affinity>` | Tool routing rules (Grep not bash grep, Edit not sed, etc.) |
| `<one_in_progress>` | Cardinality rule — one WIP item at a time |
| `<before_writing_code>` | Pre-coding checklist |
| `<writing_new_files>` | New file conventions |
| `<anti_overengineering>` | Scope creep prevention |
| `<modifying_existing_files>` | Surgical edit rules |
| `<legacy_patterns>` | How to work with older code styles |
| `<implementation_guidance>` | Per-layer guidance (schema, models, logic, controllers, views, routes) |
| `<self_doubt_checkpoints>` | Post-implementation self-review |
| `<follow_through_policy>` | Don't stop early |
| `<blocker_handling>` | BLOCKER marker protocol with dual-form naming |
| `<assumptions>` | Assumptions register |

### Testing
| Tag | Purpose |
|-----|---------|
| `<how_you_think>` | Risk-first test strategy |
| `<establish_baseline>` | Record test suite state before changes |
| `<understand_existing_tests>` | Match existing test patterns |
| `<test_patterns>` | Integration, unit, security, edge case test guidance |
| `<fixtures>` | Test data as scenarios |
| `<no_test_framework>` | Fallback for projects without test runners |
| `<after_writing_tests>` | Post-test verification |

### Verification
| Tag | Purpose |
|-----|---------|
| `<how_you_review>` | Review methodology |
| `<anti_patterns>` | Two failure modes to guard against (verification avoidance, seduced by 80%) |
| `<before_pass>` | Adversarial probe checklist before issuing READY |
| `<before_fail>` | Validation checklist before issuing NOT READY |
| `<confidence_scoring>` | 1–10 confidence score per finding; <7 becomes NOTE |
| `<hard_exclusions>` | Dated list of known false-positive patterns to skip |
| `<blocked_by_scope>` | Protocol for out-of-scope findings (record, don't patch, name owner) |
| `<mandatory_evidence>` | Every finding must quote file:line + code |
| `<consistency_checks>` | 4 mechanical grep-level checks (data-value, symbol-name, timezone, event-name) |
| `<verify_visual_output>` | Visual rendering checks for emails/PDFs/reports |
| `<think_about_production>` | Production scenario questions |
| `<check_priority_order>` | Review priority: existing code → requirements → architecture → security → code quality → framework |
| `<reporting_issues>` | Finding format and severity definitions |
| `<severity_levels>` | CRITICAL / MUST FIX (untested seam) / SHOULD FIX / IMPROVE |

### Delivery
| Tag | Purpose |
|-----|---------|
| `<how_you_think>` | Deployment safety questions |
| `<missing_information>` | Handling gaps in upstream artifacts |

## Task-notification envelope (emitted by subagents)

```xml
<task-notification>
  <status>completed|failed</status>
  <summary>One-line description</summary>
  <result>READY|READY WITH NOTES|NOT READY|BLOCKED</result>
</task-notification>
```
