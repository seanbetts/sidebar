"""Seed data plan for test users."""

from __future__ import annotations

import os
import uuid
from calendar import monthrange
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from pathlib import Path
from typing import Any

SCRATCHPAD_TITLE = "✏️ Scratchpad"


@dataclass(frozen=True)
class SeedNote:
    """Seed note payload."""

    title: str
    content: str
    folder: str
    pinned: bool = False
    tags: list[str] | None = None


@dataclass(frozen=True)
class SeedWebsite:
    """Seed website payload."""

    url: str
    title: str
    content: str
    source: str | None = None
    url_full: str | None = None
    saved_at: datetime | None = None
    published_at: datetime | None = None
    pinned: bool = False
    archived: bool = False


@dataclass(frozen=True)
class SeedConversation:
    """Seed conversation payload."""

    title: str
    messages: list[dict[str, Any]]


@dataclass(frozen=True)
class SeedMemory:
    """Seed memory payload."""

    path: str
    content: str


@dataclass(frozen=True)
class SeedTaskArea:
    """Seed task area payload."""

    key: str
    title: str


@dataclass(frozen=True)
class SeedTaskProject:
    """Seed task project payload."""

    key: str
    title: str
    area_key: str | None = None
    status: str = "active"
    notes: str | None = None


@dataclass(frozen=True)
class SeedTask:
    """Seed task payload."""

    title: str
    status: str = "inbox"
    project_key: str | None = None
    area_key: str | None = None
    notes: str | None = None
    deadline: date | None = None
    recurrence_rule: dict[str, Any] | None = None
    repeating: bool = False
    repeat_template: bool = False
    repeat_template_key: str | None = None
    next_instance_date: date | None = None


@dataclass(frozen=True)
class SeedSettings:
    """Seed user settings payload."""

    system_prompt: str
    first_message_prompt: str
    communication_style: str
    working_relationship: str
    name: str
    job_title: str
    employer: str
    location: str
    pronouns: str
    enabled_skills: list[str] | None
    tasks_ai_snapshot: str | None


@dataclass(frozen=True)
class SeedPlan:
    """Container for all seed content."""

    seed_tag: str
    title_prefix: str
    folders: list[str]
    notes: list[SeedNote]
    scratchpad: str
    websites: list[SeedWebsite]
    conversations: list[SeedConversation]
    memories: list[SeedMemory]
    task_areas: list[SeedTaskArea]
    task_projects: list[SeedTaskProject]
    tasks: list[SeedTask]
    settings: SeedSettings


def build_seed_plan(seed_tag: str, *, now: datetime | None = None) -> SeedPlan:
    """Build a deterministic seed plan."""
    timestamp = now or datetime.now(UTC)
    today = timestamp.date()
    tomorrow = today + timedelta(days=1)
    next_week = today + timedelta(days=7)
    title_prefix = f"[{seed_tag}] "

    folders = [
        "Projects",
        "Projects/sideBar",
        "Personal",
        "Research",
        "Archive/2025",
    ]

    notes = [
        SeedNote(
            title="Product roadmap",
            content=(
                "# Product roadmap\n\n"
                "## Themes\n"
                "- Improve onboarding\n"
                "- Sharper retrieval\n"
                "- Mobile polish\n\n"
                "## Next steps\n"
                "- Validate metrics\n"
                "- Capture screenshots\n"
            ),
            folder="Projects/sideBar",
            pinned=True,
            tags=[seed_tag, "roadmap", "product"],
        ),
        SeedNote(
            title="Meeting notes - Design sync",
            content=(
                "# Design sync\n\n"
                "- Align on chat layout\n"
                "- Confirm notes toolbar\n"
                "- Decide on accent colors\n"
            ),
            folder="Projects/sideBar",
            tags=[seed_tag, "meeting"],
        ),
        SeedNote(
            title="Personal goals",
            content=(
                "# Personal goals\n\n"
                "- Daily review\n"
                "- Weekly reflection\n"
                "- Ship one improvement\n"
            ),
            folder="Personal",
            tags=[seed_tag, "goals"],
        ),
        SeedNote(
            title="Research backlog",
            content=(
                "# Research backlog\n\n"
                "- Task recurrence UX\n"
                "- Offline cache strategy\n"
                "- iOS share extension flow\n"
            ),
            folder="Research",
            tags=[seed_tag, "research"],
        ),
        SeedNote(
            title="Archived draft - Old brief",
            content=(
                "# Old brief\n\n"
                "This draft was superseded by the new product brief.\n"
            ),
            folder="Archive/2025",
            tags=[seed_tag, "archive"],
        ),
    ]

    scratchpad = (
        f"# {SCRATCHPAD_TITLE}\n\n"
        "## Today\n"
        "- Capture quick ideas\n"
        "- Paste snippets\n\n"
        "## Reminders\n"
        "- Review tasks list\n"
    )

    websites = [
        SeedWebsite(
            url="https://developer.apple.com/documentation/swiftui",
            url_full="https://developer.apple.com/documentation/swiftui",
            title=f"{title_prefix}SwiftUI documentation",
            content=(
                "# SwiftUI documentation\n\n"
                "Highlights of SwiftUI layouts, state, and navigation.\n"
            ),
            source=seed_tag,
            saved_at=timestamp,
            published_at=None,
            pinned=True,
        ),
        SeedWebsite(
            url="https://supabase.com/docs",
            url_full="https://supabase.com/docs",
            title=f"{title_prefix}Supabase docs overview",
            content=(
                "# Supabase docs\n\n"
                "Authentication, database, and realtime references.\n"
            ),
            source=seed_tag,
            saved_at=timestamp - timedelta(days=3),
            archived=False,
        ),
        SeedWebsite(
            url="https://www.anthropic.com/news",
            url_full="https://www.anthropic.com/news",
            title=f"{title_prefix}Anthropic updates",
            content="# Anthropic updates\n\nRelease notes and announcements.\n",
            source=seed_tag,
            saved_at=timestamp - timedelta(days=10),
            archived=True,
        ),
    ]

    conversations = [
        SeedConversation(
            title=f"{title_prefix}Onboarding flow review",
            messages=[
                _message("user", "Draft a 3-step onboarding flow.", timestamp),
                _message(
                    "assistant",
                    (
                        "Here is a quick 3-step flow: welcome, sample chat, and goal "
                        "selection."
                    ),
                    timestamp + timedelta(seconds=3),
                ),
            ],
        ),
        SeedConversation(
            title=f"{title_prefix}Website summary",
            messages=[
                _message(
                    "user",
                    "Summarize the key ideas from the SwiftUI docs.",
                    timestamp - timedelta(minutes=12),
                ),
                _message(
                    "assistant",
                    (
                        "SwiftUI emphasizes declarative UI, state-driven updates, and "
                        "composable views."
                    ),
                    timestamp - timedelta(minutes=11, seconds=30),
                    tool_calls=[
                        {
                            "id": str(uuid.uuid4()),
                            "name": "web-save",
                            "parameters": {
                                "url": "https://developer.apple.com/documentation/swiftui"
                            },
                            "status": "success",
                            "result": {"title": "SwiftUI documentation"},
                        }
                    ],
                ),
            ],
        ),
    ]

    memories = [
        SeedMemory(
            path=f"memories/seed/{seed_tag}/preferences/communication",
            content="Prefers concise answers with bullet summaries.",
        ),
        SeedMemory(
            path=f"memories/seed/{seed_tag}/projects/sidebar",
            content="Focus on realtime chat and fast note capture.",
        ),
    ]

    task_areas = [
        SeedTaskArea(key="work", title="Work"),
        SeedTaskArea(key="personal", title="Personal"),
    ]

    task_projects = [
        SeedTaskProject(
            key="sidebar_ios",
            title="sideBar iOS",
            area_key="work",
            notes="Ship the beta experience.",
        ),
        SeedTaskProject(
            key="launch",
            title="Beta launch",
            area_key="work",
            notes="Coordinate TestFlight rollout.",
        ),
        SeedTaskProject(
            key="home",
            title="Home admin",
            area_key="personal",
            notes="Keep weekly maintenance tasks.",
        ),
    ]

    daily_rule = {"type": "daily", "interval": 1}
    weekly_rule = {"type": "weekly", "interval": 1, "weekday": 1}

    tasks = [
        SeedTask(
            title="Review onboarding checklist",
            status="inbox",
            project_key="launch",
            area_key="work",
            notes="Confirm beta testers list.",
        ),
        SeedTask(
            title="Draft beta release notes",
            status="inbox",
            project_key="launch",
            area_key="work",
            deadline=tomorrow,
            notes="Include iOS and web highlights.",
        ),
        SeedTask(
            title="Refine chat input layout",
            status="inbox",
            project_key="sidebar_ios",
            area_key="work",
            deadline=today,
            notes="Check keyboard behavior on iPhone.",
        ),
        SeedTask(
            title="Daily inbox review",
            status="inbox",
            area_key="personal",
            deadline=today,
            recurrence_rule=daily_rule,
            repeating=True,
            next_instance_date=_calculate_next_occurrence(daily_rule, today),
        ),
        SeedTask(
            title="Weekly planning session",
            status="inbox",
            area_key="personal",
            deadline=next_week,
            recurrence_rule=weekly_rule,
            repeating=True,
            next_instance_date=_calculate_next_occurrence(weekly_rule, next_week),
        ),
    ]

    settings = SeedSettings(
        system_prompt=(
            f"Seed tag: {seed_tag}\n" "You are a helpful assistant for a beta tester."
        ),
        first_message_prompt="Welcome to your seeded workspace.",
        communication_style="Concise, actionable, and friendly.",
        working_relationship="Act as a proactive co-pilot.",
        name="Alex Sample",
        job_title="Product Lead",
        employer="sideBar Labs",
        location="London",
        pronouns="they/them",
        enabled_skills=_select_seed_skills(),
        tasks_ai_snapshot=None,
    )

    return SeedPlan(
        seed_tag=seed_tag,
        title_prefix=title_prefix,
        folders=folders,
        notes=notes,
        scratchpad=scratchpad,
        websites=websites,
        conversations=conversations,
        memories=memories,
        task_areas=task_areas,
        task_projects=task_projects,
        tasks=tasks,
        settings=settings,
    )


def _select_seed_skills() -> list[str] | None:
    try:
        from api.services.skill_catalog_service import SkillCatalogService
    except ImportError:
        return None
    skills_dir_value = os.getenv("SKILLS_DIR")
    skills_dir = Path(skills_dir_value) if skills_dir_value else None
    if not skills_dir or not skills_dir.exists():
        return None
    skills = SkillCatalogService.list_skills(skills_dir)
    return [skill["id"] for skill in skills[:6]]


def _calculate_next_occurrence(rule: dict[str, Any], from_date: date) -> date:
    rule_type = rule.get("type")
    interval = max(1, int(rule.get("interval") or 1))

    if rule_type == "daily":
        return from_date + timedelta(days=interval)
    if rule_type == "weekly":
        target = int(rule.get("weekday", 0))
        python_weekday = (target + 6) % 7
        days_ahead = (python_weekday - from_date.weekday()) % 7
        if days_ahead == 0:
            days_ahead = 7 * interval
        else:
            days_ahead += 7 * (interval - 1)
        return from_date + timedelta(days=days_ahead)
    if rule_type == "monthly":
        target_day = int(rule.get("day_of_month") or from_date.day)
        month = from_date.month - 1 + interval
        year = from_date.year + month // 12
        month = month % 12 + 1
        max_day = monthrange(year, month)[1]
        return date(year, month, min(target_day, max_day))

    raise ValueError(f"Unknown recurrence type: {rule_type}")


def _message(
    role: str,
    content: str,
    timestamp: datetime,
    *,
    tool_calls: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    payload = {
        "id": str(uuid.uuid4()),
        "role": role,
        "content": content,
        "status": "complete",
        "timestamp": timestamp.isoformat(),
        "toolCalls": tool_calls,
        "error": None,
    }
    if tool_calls is None:
        payload.pop("toolCalls")
    return payload
