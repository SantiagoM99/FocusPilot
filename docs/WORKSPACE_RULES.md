# Folder and workspace rules

The owner already has Projects/Academic, Projects/Personal, Projects/NLP, and other roots. This is observed layout, not authorization to reorganize it or create new mappings automatically.

## Configuration

Let the owner select folder roots and optionally map categories to them. Existing contexts use folder bookmarks and explicit Herdr server/session/workspace IDs. Grouping is user-defined: one assignment per workspace, a shared PhD application-cycle workspace, or individual university workspaces are all valid.

## Existing environment

Link the actual folder and existing workspace. Attach resources without copying them by default. Revalidate before launch. If a workspace no longer exists, offer relink or create rather than silently substituting a similarly named one.

Revalidating a folder link means resolving its bookmark and running the identity, Trash and containment checks under "Folder links" below. A folder deleted and recreated at the same path is a "needs repair" case, not a healthy link.

Keep the minimal launch set separate from the full resource list. Starting existing work creates no new folder/workspace and opens only the selected launch set. Resume should require at most two interactions when links are healthy.

## New environment

Create a concrete SetupPlan: chosen root, proposed child path, any files and contents, workspace label/cwd, resources, and requested navigation. Show it before execution. Defaults can be saved per category after explicit user choice.

Do not impose src/results/resources directories universally. A writing assignment may only need a brief and reference links; an existing repository may require no additions. Preserve project conventions.

## Provisioning requirements

- Canonicalize and validate paths against selected roots, including traversal and symlinks. Containment: `realpath` the root and the deepest existing ancestor of the candidate path; reject `.`, `..` or a dangling symlink in the part that does not exist yet; compare components case-folded on case-insensitive volumes and after Unicode normalization. Do not rely on `URL.resolvingSymlinksInPath` or `standardizedFileURL`, which leave symlinks in a not-yet-existing path unresolved (S5 T10).
- Create folders with `mkdirat` on a directory descriptor of the root, one path component at a time, and confirm with `openat(O_NOFOLLOW)`. An existing name, including a symlink, is a collision, never an overwrite (S5 T9).
- Never overwrite existing files by default. Treat name collisions explicitly.
- Keep a record of each created artifact and workspace ID.
- A retry reconciles actual state before repeating a mutation.
- If folder creation succeeds but workspace creation fails, show partial success and let the owner retry or keep the folder.
- Never delete unrelated files or close existing workspaces as cleanup.
- Use structured process arguments; do not build shell commands from task titles.
- Do not focus a workspace automatically unless the launch flow explicitly requests it.

## Folder links

Confirmed by S5 (#5, 2026-10-14 to 2026-11-03; ad hoc signed, sandboxed and unsandboxed):

1. Always create bookmarks with `.withSecurityScope`, even while the app is unsandboxed. The same bookmark keeps working if the app is later sandboxed under the same bundle ID. A plain bookmark lost access after a reboot in the sandboxed app (error 257); security-scoped ones survived.
2. Store with each bookmark the path at creation, the inode and the volume UUID. After resolving, the link **needs repair** when:
   - resolution failed (folder deleted, or its volume unmounted);
   - the inode or volume UUID differs (the folder was deleted and recreated at the same path);
   - the folder is now in the Trash;
   - the folder is no longer inside its root.

   The inode is a heuristic (Apple says not to persist file identifiers), so a mismatch asks the owner and never acts alone.
3. When the bookmark is stale and no repair condition holds (renamed or moved within its root), re-create it while access is held, save it, and show the owner the new path.
4. Repair shows the old path and what was found, and offers: use the new location, choose again (open panel), or unlink. Never pick a similarly named folder automatically.
5. Start access only around the work, and balance every start with a stop.

Still to validate: whether bookmarks made by an ad hoc build resolve in the first Developer ID build. S5 suggests the binding is the bundle ID, but Developer ID changes the designated requirement. If they do not resolve, the repair path ("choose again") covers it. TCC-protected roots (Desktop, Documents, Downloads, iCloud Drive) and network volumes were not measured.

Herdr process launch from an unsandboxed app was proven in S4 (#4). Folder bookmarks were proven in S5 (#5). File access for provisioning, several attached Herdr clients and App Sandbox restrictions must be proven before promising seamless provisioning; a sandboxed build likely cannot run `~/.local/bin/herdr` or reach its socket.
