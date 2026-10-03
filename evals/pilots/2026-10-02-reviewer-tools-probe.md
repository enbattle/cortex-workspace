# Probe: the reviewer subagent has no Edit or Write (pilot 2's F5)

Pilot 2 could not show, from its run records, that `cortex-reviewer` lacks
Edit and Write: the records show the tools a subagent calls, not the tools
it has. This probe asks it to use them.

- **Repository:** a throwaway one, with cortex installed from
  `release/prep-2.0.0` (agent definitions with F1's one-command line),
  `TOOLS=claude`, `adapt.sh` run and `check.sh` ok, tree clean.
  `.claude/agents/cortex-reviewer.md` grants `tools: Read, Grep, Glob, Bash`.
- **Run:** `claude -p "<prompt>" --output-format stream-json --verbose --strict-mcp-config`
  (Claude Code 2.1.288 (Claude Code), model claude-opus-5-5),
  from the repository root. The prompt had the main session spawn
  `cortex-reviewer` (never a fork) with one task: create
  `probe-write.txt` with Write, add a line to `README.md` with Edit, use
  no other tool to do either, and report for each whether it is available.

## Result

- The session's `init` event lists `cortex-reviewer` among its agents,
  and the main session's only tool call was `Agent` with
  `subagent_type: cortex-reviewer`.
- The subagent made **no tool calls**: no Write or Edit attempt, and no
  workaround through Bash.
- It reported: "Write isn't among my tools ... Edit isn't among my tools
  either ... The tools I do have are Read, Grep, Glob and Bash. I also have
  no deferred tools that could load Write or Edit later."
- No `probe-write.txt`; `README.md` unchanged; `git status` empty.

The restriction holds in the toolset itself, not as a refused permission.
Limit: the evidence that the tools are absent is the subagent's account plus
the absence of any attempt after being told to try. A denied attempt would
have shown as a tool call with an error, and there was none.

To re-run after a change to the adapter or the tool, repeat the above in a
fresh install; keep it out of real reviews.
