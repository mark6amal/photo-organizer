# Photo Organizer Product Roadmap

## Product Vision

Photo Organizer should help photographers move from a large set of RAW and JPEG captures to a small set of confident keepers as quickly as possible. The product is centered on fast culling, moment-based review, and clear objective photo truths that help the user decide what is worth sending into editing.

## Core User Jobs

1. Go from raw photos to selected keepers fast, then export them into an editing workflow.
2. Scrub through travel photos quickly, focusing on the best moment instead of getting stuck on individual files.
3. Judge whether a photo is viable using practical signals like focus, exposure balance, clipping risk, and likely recoverability.

## Product Principles

1. Speed first. The main workflow should optimize for momentum and keyboard-first culling.
2. Assistive, not opinionated. The app should show evidence and guidance, not auto-pick for the user.
3. Moments over files. The default mental model should be reviewing a burst or scene as a single decision unit.
4. Export is a handoff. The app ends when the user has clean keepers ready for editing.

## Core Workflow

1. Open a folder of RAW and/or JPEG files.
2. Review photos in the culling workspace.
3. Move between moments and compare alternates inside a moment.
4. Mark photos as keep, reject, or leave them undecided.
5. Start a new round from kept photos when the user wants another pass.
6. Export keepers to a destination folder for editing.

## UX Model

### Culling Workspace

The default experience is a filmstrip-based culling workspace:

- Large centered preview for the current image
- Bottom strip of nearby frames for quick context
- Compact decision rail for quality signals
- Keep, reject, and navigation controls that work without opening side panels

### Moment Navigation

- A moment is a time-based group of nearby captures.
- Similarity clustering can further split a moment into visually similar sub-groups.
- Left and right move between moments.
- Up and down move within the current moment.
- The UI should show clear progress such as the current moment, total moments, and frame count inside the moment.

### Decision States

Each photo can be:

- `undecided`
- `kept`
- `rejected`

Kept photos drive:

- new rounds
- keep-only filtering
- export

### Quality Signals

The product should show simple, human-readable cues:

- sharpness
- exposure balance
- highlight clipping risk
- shadow clipping risk
- likely recoverability
- duplicate density inside the current moment

These signals are assistive heuristics, not hard judgments.

## Data And State Model Changes

### Decision State

Replace a plain selected-ID list as the primary source of truth with explicit decision state:

- `photoDecisions: [UUID: DecisionState]`

Derived helpers should expose:

- kept photos
- rejected photos
- undecided photos
- kept count

Compatibility helpers should remain during migration so existing views can still ask whether a photo is kept.

### Photo Quality Signals

Normalize raw technical metrics into a user-facing quality model:

- sharpness score and label
- exposure label
- highlight clipping
- shadow clipping
- recoverability hint

This model should be cached per photo and used by the culling UI.

### Moment Abstraction

Time groups remain the underlying implementation, but user-facing language should shift from “groups” to “moments.” When grouping is off, a single photo should behave like a one-photo moment so navigation stays predictable.

## Implementation Phases

### Phase 1: Documentation

- Rewrite this roadmap around fast culling and moment-based review.
- Update README messaging after the code matches the product direction.

### Phase 2: Decision Model

- Introduce `DecisionState`.
- Migrate rounds, export, and session persistence to use kept photos.

### Phase 3: Moment UX

- Reframe visible group language as moments.
- Make the filmstrip navigation moment-first by default.

### Phase 4: Culling Workspace

- Make keep and reject explicit actions in the filmstrip.
- Make the current decision state obvious.
- Keep loupe, metadata, and histogram as secondary aids.

### Phase 5: Quality Signal Layer

- Reuse existing sharpness and histogram analysis.
- Convert raw metrics into simple labels and hints.
- Surface those signals inline in the culling workspace.

### Phase 6: Export Alignment

- Make export clearly about sending keepers to editing.
- Preserve current copy behavior, RAW pairing, and folder options.

## PR Sequence

1. `docs: reframe roadmap around fast culling and moment-based review`
2. `feat: add keep/reject/undecided decision model`
3. `feat: add moment-centric navigation and presentation`
4. `feat: convert filmstrip into a culling workspace`
5. `feat: introduce objective photo quality signals`
6. `feat: add inline decision rail for quality signals`
7. `feat: align export flow with keeper-to-editing handoff`
8. `docs: update README to match culling-first positioning`

## Acceptance Criteria

1. The user can complete a keyboard-only first pass using keep, reject, and navigation.
2. Moment navigation is clear, responsive, and consistent whether grouping is on or off.
3. Quality signals read as concise guidance and help answer whether a photo is viable.
4. New rounds and export operate on kept photos only.
5. RAW plus JPEG pairing continues to work in browsing and export flows.
6. The product messaging in docs and UI matches the culling-first positioning.
