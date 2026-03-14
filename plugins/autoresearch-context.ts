import { type Plugin } from '@opencode-ai/plugin';

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

const SENTINEL_FILE = '.autoresearch-off';

export const autoresearchContext: Plugin = {
  name: 'autoresearch-context',
  description: 'Inject autoresearch context before every prompt',

  events: {
    'tui.prompt.append': async (context) => {
      // Check if sentinel file exists
      const hasSentinel = await checkSentinelFile();
      
      if (hasSentinel) {
        return;
      }

      // Check if autoresearch.md command file exists
      const hasCommandFile = await checkCommandFile();
      
      if (!hasCommandFile) {
        return;
      }

      // Inject context
      context.append(CONTEXT_INJECTION);
    },
  },
};

/**
 * Check if the sentinel file exists
 */
async function checkSentinelFile(): Promise<boolean> {
  try {
    const fs = await import('fs');
    const path = await import('path');
    
    const sentinelPath = path.join(process.cwd(), SENTINEL_FILE);
    return fs.existsSync(sentinelPath);
  } catch {
    return false;
  }
}

/**
 * Check if the autoresearch command file exists
 */
async function checkCommandFile(): Promise<boolean> {
  try {
    const fs = await import('fs');
    const path = await import('path');
    
    const commandPath = path.join(process.cwd(), 'autoresearch.md');
    return fs.existsSync(commandPath);
  } catch {
    return false;
  }
}