# -*- coding: utf-8 -*-
"""Thin, defensive wrapper around the DaVinci Resolve scripting API.

Business logic MUST NEVER call the Resolve API directly; it goes through
this adapter. Every call is wrapped so that a Resolve-side failure becomes
a warning rather than a crash. Importing this module does not require
DaVinci Resolve to be installed; ``DaVinciResolveScript`` is imported lazily
inside :meth:`ResolveAdapter.connect`.
"""

import os
from typing import Any, Dict, List, Optional, Tuple


class ResolveUnavailable(Exception):
    """Raised when the Resolve scripting bridge cannot be reached."""


def _default_api_paths():
    # type: () -> Tuple[str, str]
    api = os.environ.get(
        "RESOLVE_SCRIPT_API",
        "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting")
    lib = os.environ.get(
        "RESOLVE_SCRIPT_LIB",
        "/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/Libraries/Fusion/fusionscript.so")
    return api, lib


def connect():
    # type: () -> Any
    """Import and return the live ``resolve`` object, or raise."""
    api, lib = _default_api_paths()
    modules = os.path.join(api, "Modules")
    if modules not in __import__("sys").path:
        __import__("sys").path.append(modules)
    try:
        import DaVinciResolveScript as dvr_script  # type: ignore
    except Exception as exc:  # pragma: no cover - depends on Resolve env
        raise ResolveUnavailable(
            "Cannot import DaVinciResolveScript: %s" % exc)
    try:
        resolve = dvr_script.scriptapp("Resolve")
    except Exception as exc:  # pragma: no cover
        raise ResolveUnavailable(
            "DaVinci Resolve scripting bridge is not available: %s" % exc)
    if resolve is None:
        raise ResolveUnavailable("DaVinci Resolve is not running.")
    return resolve


class ResolveAdapter(object):
    """Defensive facade over the live Resolve object.

    Constructed with the raw ``resolve`` object (a fake may be supplied in
    tests). All public methods return safe defaults on failure and append a
    human-readable warning to :attr:`warnings`.
    """

    def __init__(self, resolve, version_string=None):
        # type: (Any, Optional[str]) -> None
        self._resolve = resolve
        self._version_string = version_string
        self.warnings = []  # type: List[str]

    # -- environment ------------------------------------------------------

    def get_version_string(self):
        # type: () -> str
        if self._version_string:
            return self._version_string
        try:
            value = self._resolve.GetVersionString()
            if value:
                self._version_string = str(value)
                return self._version_string
        except Exception as exc:
            self.warnings.append("GetVersionString failed: %s" % exc)
        self._version_string = "unknown"
        return self._version_string

    def get_current_project_name(self):
        # type: () -> Optional[str]
        project = self._get_current_project()
        if project is None:
            return None
        try:
            return str(project.GetName())
        except Exception as exc:
            self.warnings.append("project.GetName failed: %s" % exc)
            return None

    def _get_current_project(self):
        # type: () -> Optional[Any]
        try:
            pm = self._resolve.GetProjectManager()
            if pm is None:
                self.warnings.append("ProjectManager is unavailable")
                return None
            project = pm.GetCurrentProject()
            return project
        except Exception as exc:
            self.warnings.append("GetCurrentProject failed: %s" % exc)
            return None

    def _get_media_pool(self):
        # type: () -> Optional[Any]
        project = self._get_current_project()
        if project is None:
            return None
        try:
            return project.GetMediaPool()
        except Exception as exc:
            self.warnings.append("GetMediaPool failed: %s" % exc)
            return None

    # -- folders ---------------------------------------------------------

    def get_root_folder(self):
        # type: () -> Optional[Any]
        pool = self._get_media_pool()
        if pool is None:
            return None
        try:
            return pool.GetRootFolder()
        except Exception as exc:
            self.warnings.append("GetRootFolder failed: %s" % exc)
            return None

    def get_subfolder_list(self, folder):
        # type: (Any) -> List[Any]
        if folder is None:
            return []
        try:
            result = folder.GetSubFolderList()
            return list(result) if result else []
        except Exception as exc:
            self.warnings.append("GetSubFolderList failed: %s" % exc)
            return []

    def get_clip_list(self, folder):
        # type: (Any) -> List[Any]
        if folder is None:
            return []
        try:
            result = folder.GetClipList()
            return list(result) if result else []
        except Exception as exc:
            self.warnings.append("GetClipList failed: %s" % exc)
            return []

    def get_folder_name(self, folder):
        # type: (Any) -> str
        try:
            return str(folder.GetName())
        except Exception:
            return ""

    def find_subfolder(self, parent, name):
        # type: (Any, str) -> Optional[Any]
        for child in self.get_subfolder_list(parent):
            if self.get_folder_name(child) == name:
                return child
        return None

    def add_subfolder(self, parent, name):
        # type: (Any, str) -> Optional[Any]
        """Idempotently create or reuse a subfolder named ``name``."""
        existing = self.find_subfolder(parent, name)
        if existing is not None:
            return existing
        pool = self._get_media_pool()
        if pool is None:
            return None
        try:
            sub = pool.AddSubFolder(parent, name)
            if sub is not None:
                return sub
            # Some Resolve versions return None on duplicate; re-search.
            return self.find_subfolder(parent, name)
        except Exception as exc:
            self.warnings.append("AddSubFolder(%s) failed: %s" % (name, exc))
            return self.find_subfolder(parent, name)

    def set_current_folder(self, folder):
        # type: (Any) -> bool
        pool = self._get_media_pool()
        if pool is None or folder is None:
            return False
        try:
            return bool(pool.SetCurrentFolder(folder))
        except Exception as exc:
            self.warnings.append("SetCurrentFolder failed: %s" % exc)
            return False

    def get_current_folder(self):
        # type: () -> Optional[Any]
        pool = self._get_media_pool()
        if pool is None:
            return None
        try:
            return pool.GetCurrentFolder()
        except Exception as exc:
            self.warnings.append("GetCurrentFolder failed: %s" % exc)
            return None

    def add_nested_folder(self, parent, path):
        # type: (Any, List[str]) -> Any
        """Walk ``path`` creating/reusing subfolders; returns the leaf."""
        folder = parent
        for part in path or []:
            name = str(part or "").strip()
            if not name:
                continue
            folder = self.add_subfolder(folder, name)
            if folder is None:
                return None
        return folder

    # -- import & clips --------------------------------------------------

    def import_media(self, paths):
        # type: (List[str]) -> List[Any]
        pool = self._get_media_pool()
        if pool is None:
            return []
        try:
            result = pool.ImportMedia(list(paths))
            return list(result) if result else []
        except Exception as exc:
            self.warnings.append("ImportMedia failed: %s" % exc)
            return []

    # -- metadata --------------------------------------------------------

    def get_metadata(self, clip, key=None):
        # type: (Any, Optional[str]) -> Any
        try:
            if key is None:
                value = clip.GetMetadata()
            else:
                value = clip.GetMetadata(key)
            return value
        except Exception as exc:
            self.warnings.append("GetMetadata failed: %s" % exc)
            return {} if key is None else None

    def get_supported_metadata_keys(self, clip):
        # type: (Any) -> set
        """Return the set of metadata keys Resolve reports for this clip."""
        meta = self.get_metadata(clip)
        if isinstance(meta, dict):
            return set(str(k) for k in meta.keys())
        return set()

    def set_metadata(self, clip, key, value):
        # type: (Any, str, str) -> bool
        try:
            return bool(clip.SetMetadata(key, str(value)))
        except Exception as exc:
            self.warnings.append("SetMetadata(%s) failed: %s" % (key, exc))
            return False

    def set_metadata_dict(self, clip, mapping):
        # type: (Any, Dict[str, str]) -> bool
        try:
            return bool(clip.SetMetadata(mapping))
        except Exception as exc:
            self.warnings.append("SetMetadata(dict) failed: %s" % exc)
            return False

    def get_third_party_metadata(self, clip, key=None):
        # type: (Any, Optional[str]) -> Any
        try:
            if key is None:
                value = clip.GetThirdPartyMetadata()
            else:
                value = clip.GetThirdPartyMetadata(key)
            return value
        except Exception as exc:
            self.warnings.append("GetThirdPartyMetadata failed: %s" % exc)
            return {} if key is None else None

    def set_third_party_metadata(self, clip, key, value):
        # type: (Any, str, str) -> bool
        try:
            return bool(clip.SetThirdPartyMetadata(key, str(value)))
        except Exception as exc:
            self.warnings.append(
                "SetThirdPartyMetadata(%s) failed: %s" % (key, exc))
            return False

    # -- color & flags ---------------------------------------------------

    def set_clip_color(self, clip, color):
        # type: (Any, str) -> bool
        if not color:
            return False
        try:
            return bool(clip.SetClipColor(color))
        except Exception as exc:
            self.warnings.append("SetClipColor(%s) failed: %s" % (color, exc))
            return False

    def add_flag(self, clip, color):
        # type: (Any, str) -> bool
        if not color:
            return False
        try:
            return bool(clip.AddFlag(color))
        except Exception as exc:
            self.warnings.append("AddFlag(%s) failed: %s" % (color, exc))
            return False

    def get_flag_list(self, clip):
        # type: (Any) -> List[str]
        try:
            result = clip.GetFlagList()
            return [str(c) for c in result] if result else []
        except Exception as exc:
            self.warnings.append("GetFlagList failed: %s" % exc)
            return []

    def get_clip_color(self, clip):
        # type: (Any) -> str
        try:
            return str(clip.GetClipColor() or "")
        except Exception:
            return ""

    def get_clip_property(self, clip, name=None):
        # type: (Any, Optional[str]) -> Any
        try:
            if name is None:
                return clip.GetClipProperty()
            return clip.GetClipProperty(name)
        except Exception as exc:
            self.warnings.append("GetClipProperty failed: %s" % exc)
            return {} if name is None else None

    def get_media_id(self, clip):
        # type: (Any) -> str
        try:
            return str(clip.GetMediaId() or "")
        except Exception:
            return ""

    def get_clip_name(self, clip):
        # type: (Any) -> str
        try:
            return str(clip.GetName() or "")
        except Exception:
            return ""
