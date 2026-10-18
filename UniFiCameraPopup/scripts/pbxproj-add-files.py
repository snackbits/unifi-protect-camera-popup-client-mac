#!/usr/bin/env python3
"""Adds files to the app target of UniFiCameraPopup.xcodeproj (hand-maintained pbxproj).

usage: scripts/pbxproj-add-files.py [--prefix XY] <group> <first-id> <file> [<file> ...]

  --prefix  two characters for new ids (default D4 = Phase 4; Phase 5 uses E5)
  group     Services | Views/Settings | Services/Tunnel | Views/Tunnel | Source (top-level group, for resources)
  first-id  two hex digits; file n gets PBXBuildFile <prefix>1…<id+n> and PBXFileReference <prefix>2…<id+n>
  file      file name inside the group's folder

*.swift goes to the Sources phase, everything else to Resources. The groups
Services/Tunnel and Views/Tunnel are created on first use. A file already in the
project is skipped, so a second run changes nothing.
"""
import os
import re
import sys

PROJECT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                       "UniFiCameraPopup.xcodeproj", "project.pbxproj")
APP_SOURCES = "A60000000000000000000002 /* Sources */"
APP_RESOURCES = "A60000000000000000000003 /* Resources */"
# group name -> (own id, parent id, child line in the parent after which it is inserted)
GROUPS = {
    "Services/Tunnel": ("D44000000000000000000001", "A40000000000000000000005",
                        "A20000000000000000000020 /* FocusMonitor.swift */"),
    "Views/Tunnel": ("D44000000000000000000002", "A40000000000000000000006",
                     "A40000000000000000000060 /* Onboarding */"),
    "Source": ("A40000000000000000000002", None, None),
    "Services": ("A40000000000000000000005", None, None),
    "Views/Settings": ("A40000000000000000000071", None, None),
}


def main():
    args = sys.argv[1:]
    prefix = "D4"
    if args[:1] == ["--prefix"]:
        prefix, args = args[1], args[2:]
    group, first, *files = args
    s = open(PROJECT, encoding="utf-8").read()
    group_id, parent_id, after_child = GROUPS[group]

    def unique(anchor):
        count = s.count(anchor)
        if count != 1:
            sys.exit(f"anchor found {count}x, expected once: {anchor!r}")

    def block_start(object_id):
        m = re.search(r"\n\t\t" + object_id + r" /\* [^*]+ \*/ = \{", s)
        if not m:
            sys.exit(f"object {object_id} not found")
        return m.start()

    def insert_into_list(object_id, list_key, line):
        nonlocal s
        start = block_start(object_id)
        key = f"\t\t\t{list_key} = (\n"
        pos = s.index(key, start) + len(key)
        s = s[:pos] + line + s[pos:]

    if parent_id and f"\t\t{group_id} /* Tunnel */ = {{" not in s:
        child_line = f"\t\t\t\t{after_child},\n"
        unique(child_line)
        s = s.replace(child_line, child_line + f"\t\t\t\t{group_id} /* Tunnel */,\n", 1)
        anchor = "/* End PBXGroup section */"
        unique(anchor)
        s = s.replace(anchor, (
            f"\t\t{group_id} /* Tunnel */ = {{\n"
            "\t\t\tisa = PBXGroup;\n"
            "\t\t\tchildren = (\n"
            "\t\t\t);\n"
            "\t\t\tpath = Tunnel;\n"
            "\t\t\tsourceTree = \"<group>\";\n"
            "\t\t};\n"
        ) + anchor, 1)

    n = int(first, 16)
    for name in files:
        if re.search(r"path = \"?" + re.escape(name) + r"\"?;", s):
            print("already in project:", name)
            n += 1
            continue
        build_id = f"{prefix}1{n:021X}"
        ref_id = f"{prefix}2{n:021X}"
        if build_id in s or ref_id in s:
            sys.exit(f"id {build_id}/{ref_id} already used – pick another first-id")
        n += 1
        swift = name.endswith(".swift")
        phase_name = "Sources" if swift else "Resources"
        file_type = "sourcecode.swift" if swift else "text"
        for marker, line in (
            ("/* End PBXBuildFile section */",
             f"\t\t{build_id} /* {name} in {phase_name} */ = {{isa = PBXBuildFile; fileRef = {ref_id} /* {name} */; }};\n"),
            ("/* End PBXFileReference section */",
             f"\t\t{ref_id} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {file_type}; path = {name}; sourceTree = \"<group>\"; }};\n"),
        ):
            unique(marker)
            s = s.replace(marker, line + marker, 1)
        insert_into_list(group_id, "children", f"\t\t\t\t{ref_id} /* {name} */,\n")
        phase = (APP_SOURCES if swift else APP_RESOURCES).split(" ")[0]
        insert_into_list(phase, "files", f"\t\t\t\t{build_id} /* {name} in {phase_name} */,\n")
        print("added", name, build_id, ref_id)

    open(PROJECT, "w", encoding="utf-8").write(s)


if __name__ == "__main__":
    main()
