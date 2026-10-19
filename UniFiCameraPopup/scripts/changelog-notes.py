#!/usr/bin/env python3
"""Prints the „Was ist neu“ items of one version (from Services/WhatsNewService.swift) as a JSON
string – the `notes` of version.json, shown in the app's update question. Empty string when the
version has no entry.  Usage: changelog-notes.py <WhatsNewService.swift> <version>"""
import json
import re
import sys

source = open(sys.argv[1], encoding="utf-8").read()
version = sys.argv[2]
match = re.search(r'ChangelogEntry\(version: "' + re.escape(version) + r'", items: \[(.*?)\]\)', source, re.S)
items = []
if match:
    for literal in re.findall(r'"((?:[^"\\]|\\.)*)"', match.group(1)):
        items.append(json.loads('"' + literal + '"'))
print(json.dumps("\n".join("• " + item for item in items), ensure_ascii=False))
