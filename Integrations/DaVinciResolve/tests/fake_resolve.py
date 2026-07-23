# -*- coding: utf-8 -*-
"""In-memory fake of the Resolve adapter for unit tests.

Implements the same public surface as ``bridge.resolve_adapter.ResolveAdapter``
so the importer can be driven without DaVinci Resolve. Standard library only.
"""

from typing import Dict, List, Optional, Any


class FakeClip(object):
    def __init__(self, name, file_path=""):
        # type: (str, str) -> None
        self.name = name
        self.file_path = file_path
        self.metadata = {}        # type: Dict[str, str]
        self.third_party = {}     # type: Dict[str, str]
        self.clip_color = ""
        self.flags = []           # type: List[str]
        self.properties = {"File Path": file_path}  # type: Dict[str, str]

    def GetName(self):
        return self.name

    def GetMediaId(self):
        return self.name

    def GetMetadata(self, key=None):
        if key is None:
            return dict(self.metadata)
        return self.metadata.get(key)

    def SetMetadata(self, key, value=None):
        if value is None and isinstance(key, dict):
            for k, v in key.items():
                self.metadata[k] = str(v)
            return True
        self.metadata[str(key)] = str(value)
        return True

    def GetThirdPartyMetadata(self, key=None):
        if key is None:
            return dict(self.third_party)
        return self.third_party.get(key)

    def SetThirdPartyMetadata(self, key, value=None):
        if value is None and isinstance(key, dict):
            for k, v in key.items():
                self.third_party[k] = str(v)
            return True
        self.third_party[str(key)] = str(value)
        return True

    def GetClipProperty(self, name=None):
        if name is None:
            return dict(self.properties)
        return self.properties.get(name)

    def SetClipColor(self, color):
        self.clip_color = str(color)
        return True

    def GetClipColor(self):
        return self.clip_color

    def AddFlag(self, color):
        self.flags.append(str(color))
        return True

    def GetFlagList(self):
        return list(self.flags)


class FakeFolder(object):
    def __init__(self, name):
        # type: (str) -> None
        self.name = name
        self.subfolders = {}  # type: Dict[str, FakeFolder]
        self.clips = []       # type: List[FakeClip]

    def GetName(self):
        return self.name

    def GetSubFolderList(self):
        return list(self.subfolders.values())

    def GetClipList(self):
        return list(self.clips)


class FakeMediaPool(object):
    def __init__(self, root, adapter):
        # type: (FakeFolder, "FakeAdapter") -> None
        self.root = root
        self.adapter = adapter
        self.current = root

    def GetRootFolder(self):
        return self.root

    def GetCurrentFolder(self):
        return self.current

    def SetCurrentFolder(self, folder):
        self.current = folder
        return True

    def AddSubFolder(self, parent, name):
        if name in parent.subfolders:
            return parent.subfolders[name]
        sub = FakeFolder(name)
        parent.subfolders[name] = sub
        return sub

    def ImportMedia(self, paths):
        created = []
        for path in paths:
            if path in self.adapter.import_blacklist:
                continue
            import os
            name = os.path.basename(path)
            clip = FakeClip(name, file_path=path)
            self.current.clips.append(clip)
            created.append(clip)
        return created


class FakeProject(object):
    def __init__(self, name, media_pool):
        # type: (str, FakeMediaPool) -> None
        self.name = name
        self.media_pool = media_pool

    def GetName(self):
        return self.name

    def GetMediaPool(self):
        return self.media_pool


class FakeProjectManager(object):
    def __init__(self, project):
        # type: (FakeProject) -> None
        self.project = project

    def GetCurrentProject(self):
        return self.project


class FakeResolve(object):
    def __init__(self, project_manager):
        # type: (FakeProjectManager) -> None
        self.project_manager = project_manager

    def GetProjectManager(self):
        return self.project_manager

    def GetVersionString(self):
        return "21.0.1-test"


class FakeAdapter(object):
    """Drop-in replacement for ``ResolveAdapter`` in tests."""

    def __init__(self, project_name="TestProject"):
        # type: (str) -> None
        self.root = FakeFolder("Root")
        self.pool = FakeMediaPool(self.root, self)
        self.project = FakeProject(project_name, self.pool)
        self.pm = FakeProjectManager(self.project)
        self.resolve = FakeResolve(self.pm)
        self.import_blacklist = set()        # type: set
        self.warnings = []                  # type: List[str]
        self._version_string = "21.0.1-test"

    # environment
    def get_version_string(self):
        return self._version_string

    def get_current_project_name(self):
        return self.project.name

    def _get_root(self):
        return self.root

    # folders
    def get_root_folder(self):
        return self.root

    def get_subfolder_list(self, folder):
        return list(folder.subfolders.values())

    def get_clip_list(self, folder):
        return list(folder.clips)

    def get_folder_name(self, folder):
        return folder.name

    def find_subfolder(self, parent, name):
        return parent.subfolders.get(name)

    def add_subfolder(self, parent, name):
        if name in parent.subfolders:
            return parent.subfolders[name]
        sub = FakeFolder(name)
        parent.subfolders[name] = sub
        return sub

    def add_nested_folder(self, parent, path):
        folder = parent
        for part in path or []:
            name = str(part or "").strip()
            if not name:
                continue
            folder = self.add_subfolder(folder, name)
        return folder

    def set_current_folder(self, folder):
        self.pool.current = folder
        return True

    def get_current_folder(self):
        return self.pool.current

    # import
    def import_media(self, paths):
        created = []
        for path in paths:
            if path in self.import_blacklist:
                continue
            import os
            name = os.path.basename(path)
            clip = FakeClip(name, file_path=path)
            self.pool.current.clips.append(clip)
            created.append(clip)
        return created

    # metadata
    def get_metadata(self, clip, key=None):
        return clip.GetMetadata(key)

    def get_supported_metadata_keys(self, clip):
        return set(clip.metadata.keys())

    def set_metadata(self, clip, key, value):
        return clip.SetMetadata(key, value)

    def set_metadata_dict(self, clip, mapping):
        return clip.SetMetadata(mapping)

    def get_third_party_metadata(self, clip, key=None):
        return clip.GetThirdPartyMetadata(key)

    def set_third_party_metadata(self, clip, key, value):
        return clip.SetThirdPartyMetadata(key, value)

    # color & flags
    def set_clip_color(self, clip, color):
        return clip.SetClipColor(color)

    def add_flag(self, clip, color):
        return clip.AddFlag(color)

    def get_flag_list(self, clip):
        return clip.GetFlagList()

    def get_clip_color(self, clip):
        return clip.GetClipColor()

    def get_clip_property(self, clip, name=None):
        return clip.GetClipProperty(name)

    def get_media_id(self, clip):
        return clip.GetMediaId()

    def get_clip_name(self, clip):
        return clip.GetName()
