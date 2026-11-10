#!/usr/bin/env python3
"""Repair Phase 1 test wiring for Wad Alreda AutoEdit.

Run from the repository root:
    python apply_phase1.py

Creates the missing EditingEngine unit test and updates the Android scaffold
copy step in GitHub Actions. It intentionally leaves settings.dart unchanged.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
TEST_PATH = ROOT / "test" / "editing_engine_test.dart"
WORKFLOW_PATH = ROOT / ".github" / "workflows" / "build.yml"
ENGINE_PATH = ROOT / "lib" / "editing_engine.dart"
PUBSPEC_PATH = ROOT / "pubspec.yaml"

TEST_SOURCE = "import 'package:flutter_test/flutter_test.dart';\nimport 'package:auto_edit/editing_engine.dart';\n\nvoid main() {\n  group('EditingEngine automatic topic profiles', () {\n    test('selects a calm profile for religious and Seerah content', () {\n      final profile = EditingEngine.select(\n        content: 'سيرة النبي ومواقف الصحابة والتوكل على الله',\n        requestedStyle: 'auto',\n      );\n      expect(profile.topic, EditTopic.religious);\n      expect(profile.visualStyle, 'clean');\n      expect(profile.punchZoom, isFalse);\n      expect(profile.flashTransitions, isFalse);\n      expect(profile.isAutomatic, isTrue);\n    });\n\n    test('selects an energetic profile for product content', () {\n      final profile = EditingEngine.select(\n        content: 'مراجعة منتج جديد وسعره متوفر في المتجر',\n        requestedStyle: 'auto',\n      );\n      expect(profile.topic, EditTopic.product);\n      expect(profile.visualStyle, 'vivid');\n      expect(profile.punchZoom, isTrue);\n      expect(profile.flashTransitions, isTrue);\n      expect(profile.maxBroll, 5);\n    });\n\n    test('manual visual style overrides automatic topic selection', () {\n      final profile = EditingEngine.select(\n        content: 'سيرة النبي',\n        requestedStyle: 'clean',\n      );\n      expect(profile.isAutomatic, isFalse);\n      expect(profile.visualStyle, 'clean');\n    });\n\n    test('falls back to a balanced profile when topic is unclear', () {\n      final profile = EditingEngine.select(\n        content: 'A quiet moment with no clear subject',\n        requestedStyle: 'auto',\n      );\n      expect(profile.topic, EditTopic.general);\n      expect(profile.visualStyle, 'cinematic');\n      expect(profile.isAutomatic, isTrue);\n    });\n  });\n}\n"

def main() -> int:
    for required in (ENGINE_PATH, PUBSPEC_PATH, WORKFLOW_PATH):
        if not required.is_file():
            print(f"ERROR: required project file is missing: {required.relative_to(ROOT)}", file=sys.stderr)
            return 2

    pubspec = PUBSPEC_PATH.read_text(encoding="utf-8")
    if "name: auto_edit" not in pubspec:
        print("ERROR: pubspec package name is not auto_edit.", file=sys.stderr)
        return 2

    TEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    TEST_PATH.write_text(TEST_SOURCE, encoding="utf-8")

    workflow = WORKFLOW_PATH.read_text(encoding="utf-8")
    copy_line = "          cp -r lib app/lib\\n"
    if copy_line not in workflow:
        print("ERROR: Android scaffold copy step was not found in build.yml.", file=sys.stderr)
        return 3

    replacement = (
        "          cp -r lib app/lib\\n"
        "          mkdir -p app/test\\n"
        "          if [ -d test ]; then cp -r test/. app/test/; fi\\n"
    )
    if "mkdir -p app/test" not in workflow:
        workflow = workflow.replace(copy_line, replacement, 1)

    if "test/editing_engine_test.dart" not in workflow:
        print("ERROR: test file is not included in the workflow format/test steps.", file=sys.stderr)
        return 3

    WORKFLOW_PATH.write_text(workflow, encoding="utf-8")
    print("Phase 1 test wiring repaired.")
    print("Created: test/editing_engine_test.dart")
    print("Updated: .github/workflows/build.yml")
    print("Unchanged: lib/settings.dart and application source files.")
    print("Commit the two changed files, then run Build APK.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())