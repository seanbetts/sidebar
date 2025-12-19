# Agent Smith

Lightweight development environment for [Agent Skills](https://github.com/agentskills/agentskills).

## Setup

```bash
# Install dev dependencies (skills-ref for validation)
uv sync

# Verify installation - validate a single skill
.venv/bin/skills-ref validate skills/skill-creator

# Or validate all skills
./scripts/validate-all.sh
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

# Validate the new skill
.venv/bin/skills-ref validate skills/my-new-skill

# Or validate all skills
./scripts/validate-all.sh
```

## Structure

```
agent-smith/
├── skills/            # Agent skills (mounted to /skills in container)
├── scripts/           # Utility scripts
├── docker/            # Docker configuration
└── pyproject.toml     # Python project config
```

## Resources

### Learning About Agent Skills

- **[What are Skills?](https://agentskills.io/what-are-skills)** - Core concepts and how skills work
- **[Specification](https://agentskills.io/specification)** - Complete format requirements for SKILL.md files
- **[Integration Guide](https://agentskills.io/integrate-skills)** - How to incorporate skills into agents/tools

### Tools & References

- **[skills-ref](https://github.com/agentskills/agentskills/tree/main/skills-ref)** - Reference library for validating skills
- **[Skill Creator](./skills/skill-creator/SKILL.md)** - Included skill for creating new skills
- **[Example Skills](https://github.com/anthropics/skills)** - Anthropic's official skills collection

### Advanced

- **[Skill Client Integration Spec](https://github.com/anthropics/skills/blob/main/spec/skill-client-integration.md)** - Implementing filesystem-based and tool-based skill clients
- **[Agent Skills Repository](https://github.com/agentskills/agentskills)** - Main project repository
