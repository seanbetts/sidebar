"""Skills catalog API router."""
# ruff: noqa: B008

from fastapi import APIRouter, Depends
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.config import settings
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.services.agent.skills.catalog import SkillCatalogService
from api.services.store_skills_service import StoreSkillsService

router = APIRouter(prefix="/skills", tags=["skills"])


class SkillItem(BaseModel):
    """Response payload for a single skill."""

    id: str
    legacy_ids: list[str] = []
    name: str
    description: str
    category: str
    icon_key: str
    tier: str
    provider_dependency: str
    credential_requirements: list[dict[str, str | bool | None]] = []
    user_toggleable: bool = True
    default_enabled: bool = False
    installable: bool = False
    status: str = "active"
    show_required_badge: bool = True


class SkillsResponse(BaseModel):
    """Response payload for skills list."""

    catalog_version: int
    skills: list[SkillItem]


class StoreSkillProviderKey(BaseModel):
    """Install-time provider key payload for key-required skills."""

    model_config = ConfigDict(extra="forbid")
    provider: str
    api_key: str


class StoreSkillInstallRequest(BaseModel):
    """Request payload for installing a Store skill."""

    model_config = ConfigDict(extra="forbid")
    skill_id: str
    provider_keys: list[StoreSkillProviderKey] = Field(default_factory=list)


class StoreSkillInstallResponse(BaseModel):
    """Response payload for Store skill install operations."""

    skill_id: str
    installed: bool
    enabled: bool
    enabled_skills: list[str]
    installed_store_skills: list[str]


class StoreSkillUninstallRequest(BaseModel):
    """Request payload for uninstalling a Store skill."""

    model_config = ConfigDict(extra="forbid")
    skill_id: str


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
            legacy_ids=[str(item) for item in skill.get("legacy_ids", [])],
            name=str(skill["name"]),
            description=str(skill["description"]),
            category=str(skill["category"]),
            icon_key=str(skill.get("icon_key", skill["id"])),
            tier=str(skill.get("tier", "standard")),
            provider_dependency=str(skill.get("provider_dependency", "none")),
            credential_requirements=[
                {
                    str(key): value
                    for key, value in requirement.items()
                    if isinstance(key, str)
                }
                for requirement in skill.get("credential_requirements", [])
                if isinstance(requirement, dict)
            ],
            user_toggleable=bool(skill.get("user_toggleable", True)),
            default_enabled=bool(skill.get("default_enabled", False)),
            installable=bool(skill.get("installable", False)),
            status=str(skill.get("status", "active")),
            show_required_badge=bool(skill.get("show_required_badge", True)),
        )
        for skill in skills
    ]
    return SkillsResponse(
        catalog_version=SkillCatalogService.catalog_version(),
        skills=skill_items,
    )


@router.post("/store/install", response_model=StoreSkillInstallResponse)
def install_store_skill(
    payload: StoreSkillInstallRequest,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    """Install a Store skill and auto-enable it for the user."""
    result = StoreSkillsService.install_store_skill(
        db,
        user_id=user_id,
        skill_id=payload.skill_id,
        provider_keys=[item.model_dump() for item in payload.provider_keys],
    )
    return StoreSkillInstallResponse(**result)


@router.post("/store/uninstall", response_model=StoreSkillInstallResponse)
def uninstall_store_skill(
    payload: StoreSkillUninstallRequest,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    """Uninstall a Store skill and auto-disable it for the user."""
    result = StoreSkillsService.uninstall_store_skill(
        db,
        user_id=user_id,
        skill_id=payload.skill_id,
    )
    return StoreSkillInstallResponse(**result)
