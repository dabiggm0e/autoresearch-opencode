import type { Plugin } from "@opencode-ai/plugin";
import { existsSync } from "fs";
import { join } from "path";

const CONTEXT_INJECTION = `
## Autoresearch Mode (ACTIVE)

You are in autoresearch mode.

### Loop Rules
- **LOOP FOREVER** - Never ask "should I continue?"
- **Primary metric is king** - Improved → keep, worse/equal → discard
- Run experiments, log results, keep winners, discard losers
- NEVER STOP until interrupted

### Experiment Instructions
- Read autoresearch.md, autoresearch.jsonl, experiments/worklog.md for context
- If autoresearch.ideas.md exists, use it for inspiration
- User messages during experiments are steers — finish current experiment, then incorporate the idea in the next experiment
`;

const SENTINEL_FILE = ".autoresearch-off";

const autoresearchContext: Plugin = async ({ directory }) => {
  return {
    "chat.message": async (_input, output) => {
      // Check if sentinel file exists — if so, skip injection
      const sentinelPath = join(directory, SENTINEL_FILE);
      if (existsSync(sentinelPath)) {
        return;
      }

      // Check if autoresearch.md command file exists
      const commandPath = join(directory, "autoresearch.md");
      if (!existsSync(commandPath)) {
        return;
      }

      // Prepend autoresearch context to the user message
      output.parts.unshift({
        type: "text",
        text: CONTEXT_INJECTION,
      });
    },
  };
};

export default autoresearchContext;
