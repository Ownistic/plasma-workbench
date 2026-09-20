# Workbench-scoped workflows

## Context

Workbench originally limited every task and provider mapping to five global status identifiers. Plane projects can define their own workflows, and local workbenches need to remain independently configurable.

## Decision

Store ordered workflow-status definitions per local workbench. Seed each existing workbench with the five legacy identifiers so installed data remains valid. A status has a user-facing name and a terminal flag; terminal statuses stop active timers and set a task's completion timestamp. Tasks, status events, filters, and provider state mappings validate against the owning workbench's workflow.

## Consequences

Local workbenches can add statuses without a provider. Plane state mappings select from that workbench's workflow rather than a fixed list. Moving a task to a workbench that lacks its status must be rejected until a compatible status exists, preventing silent workflow changes.

## Alternatives considered

Keeping fixed global identifiers cannot represent project-specific Plane workflows. Copying Plane states directly into task rows would make the provider authoritative and break local-first workbenches. Global user-defined statuses would leak one workbench's process into another.

## Validation

Migration coverage verifies legacy status preservation and initial seeding. Repository tests verify custom-state creation, workspace isolation, terminal timer behavior, and provider mapping validation. QML tests verify local workflow controls and dynamic picker sources.
