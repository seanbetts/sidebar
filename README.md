# Agent Smith

Lightweight development environment for [Agent Skills](https://github.com/agentskills/agentskills).

## Setup

```bash
# Install dev dependencies (skills-ref for validation)
uv sync

# Verify installation
uv run skills-ref validate skills/skill-creator
```

## Docker Usage

```bash
# Start container
docker compose up -d

# Enter bash + Unix environment
docker compose exec agent-smith bash

# Inside container - skills are at /skills
ls /skills

# Stop container
docker compose down
```

## Creating Skills

Use the included skill-creator skill:

```bash
# From your local machine
python skills/skill-creator/scripts/init_skill.py my-new-skill --path ./skills

# Edit the skill
vim skills/my-new-skill/SKILL.md

# Validate
uv run skills-ref validate skills/my-new-skill
```

## Structure

```
agent-smith/
├── skills/            # Agent skills (mounted to /skills in container)
├── docker/           # Docker configuration
└── pyproject.toml    # Python project config
```

## Resources

- [Agent Skills Spec](https://github.com/agentskills/agentskills)
- [Skill Creator](./skills/skill-creator/SKILL.md)
- [Skill Client Integration](https://github.com/anthropics/skills/blob/main/spec/skill-client-integration.md)
