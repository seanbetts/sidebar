"""Compatibility alias for the installation-backed push model."""

from api.models.device_installation import DeviceInstallation

DeviceToken = DeviceInstallation

__all__ = ["DeviceToken"]
