"""Skills catalog API router."""
from fastapi import APIRouter, Depends
from pydantic import BaseModel

from api.auth import verify_bearer_token
from api.config import settings
from api.services.skill_catalog_service import SkillCatalogService


router = APIRouter(prefix="/skills", tags=["skills"])


class SkillItem(BaseModel):
    name: str
    description: str
    category: str


class SkillsResponse(BaseModel):
    skills: list[SkillItem]


@router.get("", response_model=SkillsResponse)
async def list_skills(_: str = Depends(verify_bearer_token)):
    skills = SkillCatalogService.list_skills(settings.skills_dir)
    return SkillsResponse(skills=skills)
