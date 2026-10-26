# Playbook: investigate

Read-only. Answers a question about how something works, why it was built that way, or whether something is true. Writes nothing and creates no task artifacts.

## Steps

1. Restate the question in one sentence. If it is really a request to change something, go back to the router.
2. Gather evidence within the kernel budget. Prefer primary sources: the code, tests, git history, logs, official docs. Past decisions: search Engram first.
3. If the evidence needs more than about 5 sequential lookups, send one read-only explorer and ask for at most 2k tokens with `path:line` references.
4. For "why" questions, use history (`git log -S`, `git blame`, linked PRs and issues) before theorizing.
5. For "is it safe to change X" questions, name what could break outside the diff, and prove the one fact it depends on by running real code, not by reading it.
6. Separate verified facts, assumptions, contradictions and gaps. Do not fill a gap with a guess.

## Reply format

- The answer first, in plain language.
- Evidence as `path:line` or command output.
- Facts vs. assumptions vs. open questions, when any assumptions remain.
- A recommendation only when a decision is needed, with the trade-offs.

If the investigation changed what you believe about the codebase in a non-obvious way, save it to Engram.
