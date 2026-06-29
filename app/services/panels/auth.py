from httpx import HTTPStatusError
from pasarguard import PasarguardAPI

from app.db.crud.panels import PanelsManager
from app.services.panels.cookies import format_panel_cookie_validity, panel_cookie_needs_refresh
from app.utils.security.crypto import decrypt_data

AUTH_PASSWORD = "password"
AUTH_API_KEY = "api_key"
PANEL_AUTH_PLACEHOLDER_USERNAME = "-"


def panel_uses_api_key(panel) -> bool:
    if getattr(panel, "auth_type", None) == AUTH_API_KEY:
        return True
    return (panel.cookie or "").strip().startswith("pg_key_")


def panel_needs_cookie_refresh(panel) -> bool:
    if panel_uses_api_key(panel):
        return False
    return panel_cookie_needs_refresh(panel.cookie)


def create_panel_api(panel) -> PasarguardAPI:
    if panel_uses_api_key(panel):
        return PasarguardAPI(base_url=panel.base_url, api_key=panel.cookie)
    return PasarguardAPI(base_url=panel.base_url, token=panel.cookie)


async def verify_panel_api_key(base_url, api_key) -> PasarguardAPI:
    api = PasarguardAPI(base_url=base_url, api_key=api_key.strip())
    await api.get_all_groups()
    return api


async def verify_panel_password(base_url, username, password):
    api = PasarguardAPI(base_url=base_url)
    token = await api.get_token(username=username.strip(), password=password.strip())
    authed = PasarguardAPI(base_url=base_url, token=token.access_token)
    await authed.get_all_groups()
    return authed, token.access_token


async def refresh_panel_cookie(panel) -> str:
    if panel_uses_api_key(panel):
        return panel.cookie
    api = PasarguardAPI(base_url=panel.base_url)
    token = await api.get_token(username=panel.username, password=decrypt_data(panel.password))
    await PanelsManager().update_panel(code=panel.code, cookie=token.access_token)
    return token.access_token


async def fetch_panel_groups_with_auth(panel):
    api = create_panel_api(panel)
    try:
        return await api.get_all_groups()
    except HTTPStatusError as e:
        if e.response.status_code == 401 and not panel_uses_api_key(panel):
            cookie = await refresh_panel_cookie(panel)
            return await PasarguardAPI(base_url=panel.base_url, token=cookie).get_all_groups()
        raise


def format_panel_refresh_status(panel, *, locale="fa") -> str:
    if panel_uses_api_key(panel):
        return "api_key (no refresh)" if locale == "en" else "API Key (بدون نیاز به refresh)"
    return format_panel_cookie_validity(panel.cookie, locale=locale)


def panel_auth_type_label(panel, *, short=False) -> str:
    if panel_uses_api_key(panel):
        return "API Key" if short else "🔑 API Key"
    return "User/Pass" if short else "👤 Username & Password"
