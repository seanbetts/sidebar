"""Skills catalog API router."""

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from api.auth import verify_bearer_token
from api.config import settings
from api.services.agent.skills.catalog import SkillCatalogService

router = APIRouter(prefix="/skills", tags=["skills"])


class SkillItem(BaseModel):
    """Response payload for a single skill."""

    id: str
    name: str
    description: str
    category: str
    user_toggleable: bool = True


class SkillsResponse(BaseModel):
    """Response payload for skills list."""

    skills: list[SkillItem]


@router.get("", response_model=SkillsResponse)
async def list_skills(_: str = Depends(verify_bearer_token)):
    """List available skills from the skills directory.

    Args:
        _: Authorization token (validated).

    Returns:
        Skills list payload.
    """
    skills = SkillCatalogService.list_skills(settings.skills_dir)
    skill_items = [
        SkillItem(
            id=str(skill["id"]),
            name=str(skill["name"]),
            description=str(skill["description"]),
            category=str(skill["category"]),
            user_toggleable=bool(skill.get("user_toggleable", True)),
        )
        for skill in skills
    ]
    return SkillsResponse(skills=skill_items)
