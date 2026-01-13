---
title: Agent versioning
subtitle: >-
  Safely experiment with agent configurations using branches, versions, and
  traffic deployment
---

Agent versioning allows you to experiment with different configurations of your agent without risking your production setup. Create isolated branches, test changes, and gradually roll out updates using traffic percentage deployment.

## Overview

The versioning system provides:

- **Immutable snapshots** of your agent configuration at any point in time
- **Isolated branches** for testing changes before going live
- **Traffic splitting** to gradually roll out changes to a percentage of users
- **Merging** to bring successful experiments back to main

<Note>
  Once versioning is enabled on an agent, it cannot be disabled. Consider this before enabling
  versioning on existing agents.
</Note>

## Core concepts

### Versions

A version is an immutable snapshot of an agent's configuration at a specific point in time. Each version has a unique ID (format: `agtvrsn_xxxx`) and contains:

- `conversation_config` - System prompt, LLM settings, voice configuration, tools, knowledge base
- `platform_settings` - Versioned subset including evaluation, widget, data collection, and safety settings
- `workflow` - Complete workflow definition with nodes and edges

Versions are created automatically when you save changes to a versioned agent. Once created, a version cannot be modified.

### Branches

Branches are named lines of development, similar to git branches. They allow you to work on changes in isolation before merging back to the main branch.

- Every versioned agent has a **Main** branch that cannot be deleted or archived
- Additional branches can be created from any version on the main branch
- Each branch has: id (`agtbrch_xxxx`), name, description, and a list of versions
- Branch names can contain: letters, numbers, and `() [] {} - / .` (max 140 characters)

### Traffic deployment

Traffic can be split across multiple branches by percentage, enabling gradual rollouts and A/B testing.

- Percentages must always total exactly **100%**
- Traffic routing is **deterministic** based on conversation ID (the same user consistently routes to the same branch)
- Only non-archived branches with 0% traffic can be archived

### Drafts

Unsaved changes are stored as drafts, allowing you to work on changes without immediately creating a new version.

- Drafts are **per-user, per-branch** (each team member has their own draft)
- Drafts are automatically discarded when a new version is committed
- Drafts are also discarded when merging into a branch

## Enabling versioning

Versioning is opt-in and must be explicitly enabled. You can enable it when creating a new agent or on an existing agent.

<Warning>
  Once enabled, versioning cannot be disabled. This is a permanent change to your agent.
</Warning>

### Enable when creating an agent

<CodeBlocks>
```python
from elevenlabs.client import ElevenLabs
from elevenlabs.types import *

client = ElevenLabs(api_key="your-api-key")

agent = client.conversational_ai.agents.create(
conversation_config=ConversationalConfig(
agent=AgentConfig(
first_message="Hello! How can I help you today?",
prompt=AgentPromptConfig(
prompt="You are a helpful assistant."
)
)
),
enable_versioning=True
)

print(f"Agent created with versioning: {agent.agent_id}")

```

```javascript
import { ElevenLabsClient } from '@elevenlabs/elevenlabs-js';

const client = new ElevenLabsClient({ apiKey: 'your-api-key' });

const agent = await client.conversationalAi.agents.create({
  conversationConfig: {
    agent: {
      firstMessage: 'Hello! How can I help you today?',
      prompt: {
        prompt: 'You are a helpful assistant.',
      },
    },
  },
  enableVersioning: true,
});

console.log(`Agent created with versioning: ${agent.agentId}`);

```

</CodeBlocks>

### Enable on an existing agent

<CodeBlocks>
```python
agent = client.conversational_ai.agents.update(
    agent_id="your-agent-id",
    enable_versioning_if_not_enabled=True
)
```

```javascript
const agent = await client.conversationalAi.agents.update('your-agent-id', {
  enableVersioningIfNotEnabled: true,
});
```

</CodeBlocks>

Enabling versioning creates the initial "Main" branch with the first version containing the current agent configuration.

## Working with branches

### Creating a branch

Branches can only be created from versions on the main branch. You can optionally include configuration changes that will be applied to the new branch's initial version.

<CodeBlocks>
```python
branch = client.conversational_ai.agents.branches.create(
    agent_id="your-agent-id",
    parent_version_id="agtvrsn_xxxx",
    name="experiment-v2",
    description="Testing new prompt and voice settings"
)

print(f"Created branch: {branch.created_branch_id}")
print(f"Initial version: {branch.created_version_id}")
```

```javascript
const branch = await client.conversationalAi.agents.branches.create('your-agent-id', {
  parentVersionId: 'agtvrsn_xxxx',
  name: 'experiment-v2',
  description: 'Testing new prompt and voice settings',
});

console.log(`Created branch: ${branch.createdBranchId}`);
console.log(`Initial version: ${branch.createdVersionId}`);

```

</CodeBlocks>

### Listing branches

<CodeBlocks>
```python
branches = client.conversational_ai.agents.branches.list(
    agent_id="your-agent-id"
)

for branch in branches.branches:
print(f"{branch.name}: {branch.id}")

```

```javascript
const branches = await client.conversationalAi.agents.branches.list('your-agent-id');

for (const branch of branches.branches) {
  console.log(`${branch.name}: ${branch.id}`);
}

```

</CodeBlocks>

### Getting branch details

<CodeBlocks>
```python
branch = client.conversational_ai.agents.branches.get(
    agent_id="your-agent-id",
    branch_id="agtbrch_xxxx"
)

print(f"Branch: {branch.name}")
print(f"Versions: {len(branch.versions)}")

```

```javascript
const branch = await client.conversationalAi.agents.branches.get('your-agent-id', 'agtbrch_xxxx');

console.log(`Branch: ${branch.name}`);
console.log(`Versions: ${branch.versions.length}`);

```

</CodeBlocks>

## Committing changes

When you update an agent with versioning enabled, specify the `branch_id` to create a new version on that branch.

<CodeBlocks>
```python
agent = client.conversational_ai.agents.update(
    agent_id="your-agent-id",
    branch_id="agtbrch_xxxx",
    conversation_config=ConversationalConfig(
        agent=AgentConfig(
            prompt=AgentPromptConfig(
                prompt="You are a friendly customer support agent."
            )
        )
    )
)
```

```javascript
const agent = await client.conversationalAi.agents.update(
  'your-agent-id',
  {
    conversationConfig: {
      agent: {
        prompt: {
          prompt: 'You are a friendly customer support agent.',
        },
      },
    },
  },
  { branchId: 'agtbrch_xxxx' }
);
```

</CodeBlocks>

A new version is automatically created on the specified branch, and any existing draft for that user on that branch is discarded.

## Deploying traffic

Use the deployments endpoint to distribute traffic across branches. This enables gradual rollouts and A/B testing.

<CodeBlocks>
```python
deployment = client.conversational_ai.agents.deployments.create(
    agent_id="your-agent-id",
    deployments=[
        {"branch_id": "agtbrch_main", "percentage": 90},
        {"branch_id": "agtbrch_xxxx", "percentage": 10}
    ]
)
```

```javascript
const deployment = await client.conversationalAi.agents.deployments.create('your-agent-id', {
  deployments: [
    { branchId: 'agtbrch_main', percentage: 90 },
    { branchId: 'agtbrch_xxxx', percentage: 10 },
  ],
});
```

</CodeBlocks>

<Warning>All percentages must sum to exactly 100%. The deployment will fail if they don't.</Warning>

Traffic routing is deterministic based on the conversation ID, ensuring the same user consistently reaches the same branch across sessions.

## Merging branches

When you're satisfied with changes on a branch, merge them back to the main branch.

<CodeBlocks>
```python
merge = client.conversational_ai.agents.branches.merge(
    agent_id="your-agent-id",
    source_branch_id="agtbrch_xxxx",
    target_branch_id="agtbrch_main",
    archive_source_branch=True  # Default: true
)
```

```javascript
const merge = await client.conversationalAi.agents.branches.merge('your-agent-id', 'agtbrch_xxxx', {
  targetBranchId: 'agtbrch_main',
  archiveSourceBranch: true, // Default: true
});
```

</CodeBlocks>

Merging:

- Creates a new version on the main branch with the source branch's configuration
- Optionally archives the source branch (default behavior)
- Automatically transfers traffic from the source branch to main

<Note>
  You can only merge into the main branch. Merging between non-main branches is not supported.
</Note>

## Archiving branches

Archive branches you no longer need. This helps keep your branch list organized.

<CodeBlocks>
```python
client.conversational_ai.agents.branches.update(
    agent_id="your-agent-id",
    branch_id="agtbrch_xxxx",
    archived=True
)
```

```javascript
await client.conversationalAi.agents.branches.update('your-agent-id', 'agtbrch_xxxx', {
  archived: true,
});
```

</CodeBlocks>

<Warning>
  You cannot archive a branch that has traffic allocated to it. Remove all traffic before archiving.
</Warning>

Archived branches can be unarchived by setting `archived=False`.

## Retrieving specific versions

You can retrieve an agent at a specific version or branch tip.

### Get agent at specific version

<CodeBlocks>
```python
agent = client.conversational_ai.agents.get(
    agent_id="your-agent-id",
    version_id="agtvrsn_xxxx"
)
```

```javascript
const agent = await client.conversationalAi.agents.get('your-agent-id', {
  versionId: 'agtvrsn_xxxx',
});
```

</CodeBlocks>

### Get agent at branch tip

<CodeBlocks>
```python
agent = client.conversational_ai.agents.get(
    agent_id="your-agent-id",
    branch_id="agtbrch_xxxx"
)
```

```javascript
const agent = await client.conversationalAi.agents.get('your-agent-id', {
  branchId: 'agtbrch_xxxx',
});
```

</CodeBlocks>

### Include draft changes

<CodeBlocks>
```python
agent = client.conversational_ai.agents.get(
    agent_id="your-agent-id",
    branch_id="agtbrch_xxxx",
    include_draft=True
)
```

```javascript
const agent = await client.conversationalAi.agents.get('your-agent-id', {
  branchId: 'agtbrch_xxxx',
  includeDraft: true,
});
```

</CodeBlocks>

## Settings reference

### Versioned settings

These settings can differ between versions and branches:

| Category                        | Settings                                                                                                                                                                                                                                                                                                      |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Conversation config**         | System prompt, agent personality, LLM selection and parameters, voice settings (TTS model, voice ID), tools configuration, knowledge base, first message, language settings, turn detection, interruption settings                                                                                            |
| **Versioned platform settings** | `evaluation` - evaluation criteria, `widget` - widget appearance and behavior, `data_collection` - structured data extraction, `overrides` - conversation initiation overrides, `workspace_overrides` - webhooks configuration, `testing` - test configurations, `safety` - guardrails (IVC/non-IVC settings) |
| **Workflow**                    | Complete workflow definition (nodes and edges)                                                                                                                                                                                                                                                                |

### Per-agent settings

These settings are shared across all versions:

| Setting        | Description                                                       |
| -------------- | ----------------------------------------------------------------- |
| `name`, `tags` | Agent name and tags (only updated when committing to main branch) |
| `auth`         | Authentication settings and allowlist                             |
| `call_limits`  | Concurrency and daily limits                                      |
| `privacy`      | Retention settings and zero-retention mode                        |
| `ban`          | Ban status (admin only)                                           |

<Note>
  Changes to name and tags on non-main branches don't persist to the agent until merged to main.
</Note>

## Best practices

<Steps>
  <Step title="Create tests before branching">
    Set up [automated tests](/docs/agents-platform/customization/agent-testing) that capture
    expected behavior before creating a new branch. This establishes a baseline and helps catch
    regressions early when iterating on your experiment.
  </Step>
  <Step title="Use descriptive branch names">
    Choose branch names that clearly communicate the purpose of the experiment. Include the feature
    name, hypothesis, or ticket number for easy reference (e.g., `feature/new-greeting-flow` or
    `experiment/shorter-responses`).
  </Step>
  <Step title="Document branch purposes">
    Use the branch description field to explain what hypothesis you're testing, what metrics define
    success, and any dependencies or considerations. This helps team members understand active
    experiments.
  </Step>
  <Step title="Use drafts for work-in-progress">
    Save drafts frequently while iterating on changes. This preserves your work without creating
    unnecessary versions. Only commit when you're ready to test or deploy.
  </Step>
  <Step title="Start with small traffic percentages">
    When deploying a new branch, begin with 5-10% of traffic. This limits exposure if issues arise
    while still providing meaningful data.
  </Step>
  <Step title="Monitor key metrics before increasing traffic">
    Use the [analytics dashboard](/docs/agents-platform/dashboard) to compare branch performance.
    Look for call completion rates, average conversation duration, success evaluation scores, and
    tool execution rates. Only increase traffic when metrics meet or exceed your main branch
    baseline.
  </Step>
  <Step title="Increase traffic gradually">
    Scale up traffic in increments (10% → 25% → 50% → 100%) as confidence grows. This approach
    minimizes risk while validating performance at each stage.
  </Step>
  <Step title="Keep branches short-lived">
    Merge successful experiments promptly to avoid configuration drift. Long-running branches become
    harder to merge and may conflict with other changes made to main.
  </Step>
</Steps>

## Next steps

<CardGroup cols={2}>
  <Card title="Testing" href="/docs/agents-platform/customization/agent-testing">
    Set up automated tests for your agent versions
  </Card>
  <Card title="Analytics" href="/docs/agents-platform/dashboard">
    Monitor performance across different branches
  </Card>
  <Card title="Conversation Analysis" href="/docs/agents-platform/customization/agent-analysis">
    Analyze conversations to compare branch performance
  </Card>
  <Card title="CLI" href="/docs/agents-platform/operate/cli">
    Manage versioning from the command line
  </Card>
</CardGroup>
