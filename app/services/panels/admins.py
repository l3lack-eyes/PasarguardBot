"""Pasarguard panel admin (reseller) API helpers."""

from __future__ import annotations

import json
import secrets
import string
from typing import Any

from httpx import HTTPStatusError
from pasarguard import AdminCreate, AdminModify, PasarguardAPI, RoleLimits

from app.db.crud.reseller_plans import ResellerPlanManager
from app.db.models.reseller_plans import ResellerPlan
from app.logger import get_logger
from app.services.panels.auth import create_panel_api, panel_uses_api_key, refresh_panel_cookie
from app.utils.formatting.conversions import day_to_timestamp, gigabytes_to_bytes

log = get_logger(__name__)

_SPECIAL_CHARS = "!@#$%^&*()-_=+"
_UPPER = string.ascii_uppercase
_LOWER = string.ascii_lowercase
_DIGITS = string.digits
_SAFE_ALPHABET = _UPPER + _LOWER + _DIGITS + _SPECIAL_CHARS


def generate_admin_password(length: int = 16, *, username: str | None = None) -> str:
    """Generate a password that satisfies Pasarguard panel policy."""
    length = max(length, 12)

    def _build() -> str:
        parts = [
            secrets.choice(_UPPER),
            secrets.choice(_UPPER),
            secrets.choice(_LOWER),
            secrets.choice(_LOWER),
            secrets.choice(_DIGITS),
            secrets.choice(_DIGITS),
            secrets.choice(_SPECIAL_CHARS),
        ]
        while len(parts) < length:
            parts.append(secrets.choice(_SAFE_ALPHABET))
        secrets.SystemRandom().shuffle(parts)
        return "".join(parts)

    for _ in range(32):
        password = _build()
        if '"' in password:
            continue
        if username and username.lower() in password.lower():
            continue
        return password

    # Fallback: fixed strong pattern if random attempts fail username collision checks
    suffix = secrets.token_hex(4)
    return f"Pg{suffix[0].upper()}A{suffix[1].upper()}b{suffix[2]}c{suffix[3]}!{suffix[4:8]}"


def _panel_token(panel) -> str:
    return panel.cookie


async def _with_auth_retry(panel, operation):
    api = create_panel_api(panel)
    token = _panel_token(panel)
    try:
        return await operation(api, token)
    except HTTPStatusError as e:
        if e.response.status_code == 401 and not panel_uses_api_key(panel):
            token = await refresh_panel_cookie(panel)
            api = PasarguardAPI(base_url=panel.base_url, token=token)
            return await operation(api, token)
        raise


async def fetch_panel_roles(panel) -> list[dict[str, Any]]:
    async def _fetch(api: PasarguardAPI, token: str):
        resp = await api.get_roles_simple(token=token)
        return [{"id": r.id, "name": r.name, "is_owner": bool(getattr(r, "is_owner", False))} for r in resp.roles]

    try:
        return await _with_auth_retry(panel, _fetch)
    except HTTPStatusError as e:
        log.error("Failed to fetch panel roles panel=%s status=%s", panel.code, e.response.status_code)
        return []


async def admin_username_exists(panel, username: str) -> bool:
    username = (username or "").strip()
    if not username:
        return False

    async def _check(api: PasarguardAPI, token: str):
        resp = await api.get_admins(token=token, username=username, limit=1)
        return bool(resp.admins)

    try:
        return await _with_auth_retry(panel, _check)
    except HTTPStatusError:
        return False


async def get_reseller_admin(panel, username: str):
    async def _get(api: PasarguardAPI, token: str):
        resp = await api.get_admins(token=token, username=username, limit=1)
        return resp.admins[0] if resp.admins else None

    return await _with_auth_retry(panel, _get)


def _build_role_limits(plan: ResellerPlan, max_users: int | None = None) -> RoleLimits | None:
    overrides = ResellerPlanManager.parse_json_field(plan.permission_overrides)
    limits_data: dict[str, Any] = {}
    if isinstance(overrides, dict):
        limits_data.update(overrides)
    effective_max_users = max_users if max_users is not None else plan.max_users
    if effective_max_users and effective_max_users > 0:
        limits_data.setdefault("max_users", effective_max_users)
    if not limits_data:
        return RoleLimits(max_users=effective_max_users) if effective_max_users else None
    return RoleLimits(**limits_data)


def build_admin_create_payload(
    plan: ResellerPlan,
    *,
    username: str,
    password: str,
    telegram_id: int,
    data_limit: int | None = None,
    max_users: int | None = None,
) -> AdminCreate:
    effective_data_limit = data_limit if data_limit is not None else int(plan.data_limit or 0)
    permission_overrides = _build_role_limits(plan, max_users=max_users)
    payload_kwargs: dict[str, Any] = {
        "username": username.strip(),
        "password": password,
        "role_id": int(plan.role_id),
        "note": str(telegram_id),
    }
    if effective_data_limit > 0:
        payload_kwargs["data_limit"] = effective_data_limit
    if permission_overrides is not None:
        payload_kwargs["permission_overrides"] = permission_overrides
    return AdminCreate(**payload_kwargs)


async def create_reseller_admin(panel, admin: AdminCreate):
    async def _create(api: PasarguardAPI, token: str):
        return await api.create_admin(admin=admin, token=token)

    return await _with_auth_retry(panel, _create)


async def modify_reseller_admin(panel, username: str, admin: AdminModify):
    async def _modify(api: PasarguardAPI, token: str):
        return await api.modify_admin(username=username, admin=admin, token=token)

    return await _with_auth_retry(panel, _modify)


async def suspend_reseller_admin(panel, username: str):
    return await modify_reseller_admin(panel, username, AdminModify(status="disabled"))


async def activate_reseller_admin(panel, username: str):
    return await modify_reseller_admin(panel, username, AdminModify(status="active"))


async def reset_reseller_admin_password(panel, username: str) -> str:
    password = generate_admin_password(username=username)
    await modify_reseller_admin(panel, username, AdminModify(password=password))
    return password


def _user_belongs_to_admin(user, *, admin_id: int | None, admin_username: str) -> bool:
    admin = getattr(user, "admin", None)
    if not admin:
        return False
    if admin_id and getattr(admin, "id", None) == admin_id:
        return True
    return bool(admin_username and getattr(admin, "username", None) == admin_username)


async def list_reseller_admin_users(panel, *, admin_id: int | None, admin_username: str) -> list:
    async def _list(api: PasarguardAPI, token: str):
        matched = []
        offset = 0
        limit = 200
        while True:
            resp = await api.get_users(token=token, offset=offset, limit=limit)
            users = getattr(resp, "users", None) or []
            if not users:
                break
            for user in users:
                if _user_belongs_to_admin(user, admin_id=admin_id, admin_username=admin_username):
                    matched.append(user)
            total = int(getattr(resp, "total", 0) or 0)
            offset += limit
            if offset >= total or len(users) < limit:
                break
        return matched

    return await _with_auth_retry(panel, _list)


async def delete_reseller_admin_users(panel, *, admin_id: int | None, admin_username: str) -> int:
    from pasarguard import BulkUsersSelection

    users = await list_reseller_admin_users(panel, admin_id=admin_id, admin_username=admin_username)
    user_ids = [int(u.id) for u in users if getattr(u, "id", None)]
    if not user_ids:
        return 0

    async def _delete(api: PasarguardAPI, token: str):
        deleted = 0
        for offset in range(0, len(user_ids), 100):
            chunk = user_ids[offset : offset + 100]
            await api.bulk_delete_users(BulkUsersSelection(ids=chunk), token=token)
            deleted += len(chunk)
        return deleted

    return await _with_auth_retry(panel, _delete)


async def remove_reseller_admin(panel, username: str) -> None:
    async def _remove(api: PasarguardAPI, token: str):
        await api.remove_admin(token=token, username=username)

    await _with_auth_retry(panel, _remove)


async def purge_reseller_admin(panel, account) -> tuple[int, bool]:
    """Delete sub-users and remove the panel admin. Returns (deleted_users_count, admin_removed)."""
    deleted_users = 0
    admin_removed = False
    try:
        deleted_users = await delete_reseller_admin_users(
            panel,
            admin_id=getattr(account, "panel_admin_id", None),
            admin_username=account.username,
        )
    except Exception as exc:
        log.error("delete reseller admin users failed username=%s: %s", account.username, exc)

    try:
        await remove_reseller_admin(panel, account.username)
        admin_removed = True
    except Exception as exc:
        log.error("remove reseller admin failed username=%s: %s", account.username, exc)

    return deleted_users, admin_removed


def compute_reseller_data_limit(plan: ResellerPlan, volume: float | None) -> int:
    if plan.pricing_mode in ("per_gb", "per_tb") and volume is not None and volume > 0:
        if plan.pricing_mode == "per_tb":
            return int(gigabytes_to_bytes(volume * 1024))
        return int(gigabytes_to_bytes(volume))
    return int(plan.data_limit or 0)


def compute_reseller_expiration(plan: ResellerPlan) -> int | None:
    if plan.duration and plan.duration > 0:
        return day_to_timestamp(int(plan.duration))
    return None


def format_allowed_groups_json(group_ids: list[int] | None) -> str | None:
    if not group_ids:
        return None
    return json.dumps(group_ids, ensure_ascii=False)
