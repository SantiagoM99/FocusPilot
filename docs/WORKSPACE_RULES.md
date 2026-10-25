# Folder and workspace rules

The owner already has Projects/Academic, Projects/Personal, Projects/NLP, and other roots. This is observed layout, not authorization to reorganize it or create new mappings automatically.

## Configuration

Let the owner select folder roots and optionally map categories to them. Existing contexts use folder bookmarks and explicit Herdr server/session/workspace IDs. Grouping is user-defined: one assignment per workspace, a shared PhD application-cycle workspace, or individual university workspaces are all valid.

## Existing environment

Link the actual folder and existing workspace. Attach resources without copying them by default. Revalidate before launch. If a workspace no longer exists, offer relink or create rather than silently substituting a similarly named one.

Keep the minimal launch set separate from the full resource list. Starting existing work creates no new folder/workspace and opens only the selected launch set. Resume should require at most two interactions when links are healthy.

## New environment

Create a concrete SetupPlan: chosen root, proposed child path, any files and contents, workspace label/cwd, resources, and requested navigation. Show it before execution. Defaults can be saved per category after explicit user choice.

Do not impose src/results/resources directories universally. A writing assignment may only need a brief and reference links; an existing repository may require no additions. Preserve project conventions.

## Provisioning requirements

- Canonicalize and validate paths against selected roots, including traversal and symlinks.
- Never overwrite existing files by default. Treat name collisions explicitly.
- Keep a record of each created artifact and workspace ID.
- A retry reconciles actual state before repeating a mutation.
- If folder creation succeeds but workspace creation fails, show partial success and let the owner retry or keep the folder.
- Never delete unrelated files or close existing workspaces as cleanup.
- Use structured process arguments; do not build shell commands from task titles.
- Do not focus a workspace automatically unless the launch flow explicitly requests it.

Herdr process launch from an unsandboxed app was proven in S4 (#4). File access, bookmarks (S5, #5), several attached Herdr clients and App Sandbox restrictions must be proven before promising seamless provisioning; a sandboxed build likely cannot run `~/.local/bin/herdr` or reach its socket.
