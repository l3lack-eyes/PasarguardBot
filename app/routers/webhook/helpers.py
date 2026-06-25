"""
Helper functions for webhook handlers.
"""

from app.db.crud.panels import PanelsManager
from app.db.crud.services import ServiceCRUD
from app.logger import get_logger

logger = get_logger(__name__)


async def find_service_by_username(username: str) -> tuple[bool, any, any]:
    """
    Find service by username.

    Args:
    username: username of the user in the panel

    Returns:
    tuple: (success, service, panel) - if successful (True, service, panel) otherwise (False, None, None)
    """
    service_crud = ServiceCRUD()
    panels_manager = PanelsManager()
    all_panels = await panels_manager.get_all_panels()
    for panel in all_panels:
        success, service = await service_crud.get_service_by_username_and_panel(username, panel.code)
        if success:
            return True, service, panel

    logger.warning(f"Service not found for username: {username}")
    return False, None, None
