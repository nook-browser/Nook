# CLAUDE.sessions.md

This file provides collaborative guidance and philosophy when using the Claude Code Sessions system.

## Collaboration Philosophy

**Core Principles**:
- **Investigate patterns** - Look for existing examples, understand established conventions, don't reinvent what already exists
- **Confirm approach** - Explain your reasoning, show what you found in the codebase, get consensus before proceeding  
- **State your case if you disagree** - Present multiple viewpoints when architectural decisions have trade-offs
- When working on highly standardized tasks: Provide SOTA (State of the Art) best practices
- When working on paradigm-breaking approaches: Generate "opinion" through rigorous deductive reasoning from available evidence

## Task Management

### Best Practices
- One task at a time (check .claude/state/current_task.json)
- Update work logs as you progress  
- Mark todos as completed immediately after finishing

### Quick State Checks
```bash
cat .claude/state/current_task.json  # Shows current task
git branch --show-current             # Current branch/task
```

### current_task.json Format

**ALWAYS use this exact format for .claude/state/current_task.json:**
```json
{
  "task": "task-name",        // Just the task name, NO path, NO .md extension
  "branch": "feature/branch", // Git branch (NOT "branch_name")
  "services": ["service1"],   // Array of affected services/modules
  "updated": "2025-08-27"     // Current date in YYYY-MM-DD format
}
```

**Common mistakes to avoid:**
- ❌ Using `"task_file"` instead of `"task"`
- ❌ Using `"branch_name"` instead of `"branch"`  
- ❌ Including path like `"tasks/m-task.md"`
- ❌ Including `.md` file extension

## Using Specialized Agents

You have specialized subagents for heavy lifting. Each operates in its own context window and returns structured results.

### Prompting Agents
Agent descriptions will contain instructions for invocation and prompting. In general, it is safer to issue lightweight prompts. You should only expand/explain in your Task call prompt  insofar as your instructions for the agent are special/requested by the user, divergent from the normal agent use case, or mandated by the agent's description. Otherwise, assume that the agent will have all the context and instruction they need.

Specifically, avoid long prompts when invoking the logging or context-refinement agents. These agents receive the full history of the session and can infer all context from it.

### Available Agents

1. **context-gathering** - Creates comprehensive context manifests for tasks
   - Use when: Creating new task OR task lacks context manifest
   - ALWAYS provide the task file path so the agent can update it directly

2. **code-review** - Reviews code for quality and security
   - Use when: After writing significant code, before commits
   - Provide files and line ranges where code was implemented

3. **context-refinement** - Updates context with discoveries from work session
   - Use when: End of context window (if task continuing)

4. **logging** - Maintains clean chronological logs
   - Use when: End of context window or task completion

5. **service-documentation** - Updates service CLAUDE.md files
   - Use when: After service changes

### Agent Principles
- **Delegate heavy work** - Let agents handle file-heavy operations
- **Be specific** - Give agents clear context and goals
- **One agent, one job** - Don't combine responsibilities

## Code Philosophy

### Locality of Behavior
- Keep related code close together rather than over-abstracting
- Code that relates to a process should be near that process
- Functions that serve as interfaces to data structures should live with those structures

### Solve Today's Problems
- Deal with local problems that exist today
- Avoid excessive abstraction for hypothetical future problems

### Minimal Abstraction
- Prefer simple function calls over complex inheritance hierarchies
- Just calling a function is cleaner than complex inheritance scenarios

### Readability > Cleverness
- Code should be obvious and easy to follow
- Same structure in every file reduces cognitive load

## Protocol Management

### CRITICAL: Protocol Recognition Principle

**When the user mentions protocols:**

1. **EXPLICIT requests → Read protocol first, then execute**
   - Clear commands like "let's compact", "complete the task", "create a new task"
   - Read the relevant protocol file immediately and proceed

2. **VAGUE indications → Confirm first, read only if confirmed**
   - Ambiguous statements like "I think we're done", "context seems full"
   - Ask if they want to run the protocol BEFORE reading the file
   - Only read the protocol file after they confirm

**Never attempt to run protocols from memory. Always read the protocol file before executing.**

### Protocol Files and Recognition

These protocols guide specific workflows:

1. **sessions/protocols/task-creation.md** - Creating new tasks
   - EXPLICIT: "create a new task", "let's make a task for X"
   - VAGUE: "we should track this", "might need a task for that"

2. **sessions/protocols/task-startup.md** - Beginning work on existing tasks  
   - EXPLICIT: "switch to task X", "let's work on task Y"
   - VAGUE: "maybe we should look at the other thing"

3. **sessions/protocols/task-completion.md** - Completing and closing tasks
   - EXPLICIT: "complete the task", "finish this task", "mark it done"
   - VAGUE: "I think we're done", "this might be finished"

4. **sessions/protocols/context-compaction.md** - Managing context window limits
   - EXPLICIT: "let's compact", "run context compaction", "compact and restart"
   - VAGUE: "context is getting full", "we're using a lot of tokens"

### Behavioral Examples

**Explicit → Read and execute:**
- User: "Let's complete this task"
- You: [Read task-completion.md first] → "I'll complete the task now. Running the logging agent..."

**Vague → Confirm before reading:**
- User: "I think we might be done here"
- You: "Would you like me to run the task completion protocol?"
- User: "Yes"
- You: [NOW read task-completion.md] → "I'll complete the task now..."
