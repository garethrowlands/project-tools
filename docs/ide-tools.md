# IDE tools

**`bin/ide`** — opens the appropriate IDE (VS Code or IntelliJ IDEA) for the git root of a given path or file (or `$PWD`). Detects the IDE from project files (`pom.xml`, `.idea`, `.vscode`, etc.).

**`bin/close-project`** — inverse of `ide`: closes the IDE window for a given project path (or `$PWD`). When called with no argument, also closes the current kitty pane. Uses `System Events` + close-button click for VS Code (no AppleScript dictionary).

**`bin/project-web`** — opens the web page for a project (git root of a given path, or `$PWD`) in the browser. Before opening anything, checks via AppleScript whether a Microsoft Edge tab already has that repo's URL (or a sub-page under it, e.g. an open issue/PR) open, and if so focuses that tab/window instead of opening a new one. Otherwise detects the origin remote's host and dispatches: GitLab remotes use `glab repo view -w`, GitHub remotes use `gh repo view -w`, anything else falls back to deriving an `https://` URL from the remote (handling both `git@host:owner/repo.git` and `https://host/owner/repo.git` forms) and `open`ing it.
