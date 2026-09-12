# Copyright (c) Trieflow LLC. Licensed under the MIT License.
"""Inspect packaged entrypoints and .NET dependency files; never claim startup from file inspection."""
import argparse
import json
import hashlib
import re
import zipfile
from pathlib import Path, PurePosixPath
import struct
import xml.etree.ElementTree as ET


class PayloadError(ValueError):
    pass


ENTRYPOINTS = ("FolderSail.exe", "Files.App.Server/Files.App.Server.exe")
HOST_FILES = ("coreclr.dll", "clrjit.dll", "hostfxr.dll", "hostpolicy.dll", "System.Private.CoreLib.dll")


FOUNDATION = "{http://schemas.microsoft.com/appx/manifest/foundation/windows10}"


def version_tuple(value):
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){3}", value or ""):
        raise PayloadError("Invalid package version: " + str(value))
    result = tuple(map(int, value.split(".")))
    if any(part > 65535 for part in result): raise PayloadError("Package version exceeds UInt16: " + value)
    return result


def declared_frameworks(manifest):
    if manifest.tag != FOUNDATION + "Package": raise PayloadError("Expected a Windows package manifest")
    dependencies = [dict(e.attrib) for e in manifest.findall(FOUNDATION + "Dependencies/" + FOUNDATION + "PackageDependency")]
    if not any(re.fullmatch(r"Microsoft\.WindowsAppRuntime(?:\.[0-9]+)+", e.get("Name", "")) for e in dependencies):
        raise PayloadError("Windows App Runtime framework dependency is required: WindowsAppSDKSelfContained=false")
    names = set()
    for dependency in dependencies:
        name = dependency.get("Name", "")
        if not name or name in names: raise PayloadError("Missing or duplicate framework dependency identity: " + name)
        if "Publisher" in dependency and not dependency["Publisher"]: raise PayloadError("Framework dependency publisher is empty")
        names.add(name); version_tuple(dependency.get("MinVersion"))
    return dependencies


def archive_manifest(path):
    with zipfile.ZipFile(path) as archive:
        candidates = [e for e in archive.infolist() if e.filename.casefold() == "appxmanifest.xml"]
        if len(candidates) != 1 or candidates[0].file_size > 2 * 1024 * 1024:
            raise PayloadError("Missing, ambiguous or oversized archive manifest: " + str(path))
        return ET.fromstring(archive.read(candidates[0]))


def sha256(path):
    with Path(path).open("rb") as stream:
        digest = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b""): digest.update(block)
        return digest.hexdigest()


def match_framework_archives(manifest, dependency_directory):
    required = declared_frameworks(manifest)
    identity = manifest.find(FOUNDATION + "Identity")
    if identity is None or identity.get("ProcessorArchitecture") != "x64":
        raise PayloadError("The main package must declare x64 architecture")
    directory = Path(dependency_directory).resolve()
    if not directory.is_dir(): raise PayloadError("Supplied framework dependency directory is missing")
    supplied = []
    for archive in sorted(directory.iterdir()):
        if archive.suffix.lower() not in (".msix", ".appx"): continue
        if archive.is_symlink() or not archive.is_file(): raise PayloadError("Dependency archive is not a regular file")
        candidate = archive_manifest(archive)
        candidate_id = candidate.find(FOUNDATION + "Identity")
        framework = candidate.find(FOUNDATION + "Properties/" + FOUNDATION + "Framework")
        if candidate_id is None or framework is None or (framework.text or "").strip().lower() != "true":
            raise PayloadError("Supplied dependency is not a framework package: " + archive.name)
        attributes = dict(candidate_id.attrib)
        for key in ("Name", "Publisher", "ProcessorArchitecture", "Version"):
            if not attributes.get(key): raise PayloadError("Dependency identity lacks " + key + ": " + archive.name)
        version_tuple(attributes["Version"])
        supplied.append({"identity": attributes, "path": str(archive), "sha256": sha256(archive)})
    matches = []
    for dependency in required:
        candidates = [item for item in supplied if item["identity"]["Name"] == dependency["Name"]
            and (not dependency.get("Publisher") or item["identity"]["Publisher"] == dependency["Publisher"])
            and version_tuple(item["identity"]["Version"]) >= version_tuple(dependency["MinVersion"])
            and item["identity"]["ProcessorArchitecture"] in ("x64", "neutral")]
        if len(candidates) != 1:
            raise PayloadError("Expected exactly one compatible supplied framework for " + dependency["Name"] + "; found " + str(len(candidates)))
        matches.append({"requirement": dependency, **candidates[0]})
    return {"manifest_to_artifact_matching_passed": True, "architecture": "x64", "frameworks": matches,
            "supplied_archive_count": len(supplied), "framework_registration_tested": False}


def relative_path(value):
    value = value.replace("\\", "/")
    path = PurePosixPath(value)
    if not value or path.is_absolute() or any(p in ("", ".", "..") or ":" in p or p.rstrip(" .") != p for p in value.split("/")):
        raise PayloadError("Unsafe package path: " + value)
    return path.as_posix()


def verify_required_names(names):
    present = {relative_path(p).casefold() for p in names}
    for entry in ENTRYPOINTS:
        if entry.casefold() not in present:
            raise PayloadError("Missing declared executable: " + entry)
    for entry in ENTRYPOINTS:
        base = PurePosixPath(entry).parent
        for filename in HOST_FILES:
            item = str(base / filename)
            if item.casefold() not in present:
                raise PayloadError("Missing self-contained runtime file: " + item)


def verify(root, runtime_version, dependency_directory=None):
    root = Path(root).resolve()
    files = {}
    for item in root.rglob("*"):
        if item.is_symlink(): raise PayloadError("Package contains a link: " + str(item))
        if item.is_file():
            relative = relative_path(item.relative_to(root).as_posix())
            if relative.casefold() in files: raise PayloadError("Ambiguous package filename: " + relative)
            files[relative.casefold()] = item
    verify_required_names(files)

    def require(relative):
        normalized = relative_path(str(relative))
        item = files.get(normalized.casefold())
        if item is None or item.stat().st_size == 0: raise PayloadError("Missing or empty package file: " + normalized)
        return item

    def document(relative):
        try: return json.loads(require(relative).read_text(encoding="utf-8-sig"))
        except (ValueError, UnicodeError) as error: raise PayloadError("Invalid package JSON: " + str(relative)) from error

    def require_x64(relative):
        with require(relative).open("rb") as stream:
            header = stream.read(64)
            if len(header) < 64 or header[:2] != b"MZ": raise PayloadError("Expected x64 PE file: " + str(relative))
            offset = struct.unpack_from("<I", header, 60)[0]
            stream.seek(offset); signature = stream.read(6)
            if len(signature) != 6 or signature[:4] != b"PE\0\0" or struct.unpack_from("<H", signature, 4)[0] != 0x8664:
                raise PayloadError("Expected x64 PE file: " + str(relative))

    manifest = ET.parse(require("AppxManifest.xml")).getroot()
    declared = []
    for element in manifest.iter():
        if "Executable" in element.attrib: declared.append(relative_path(element.attrib["Executable"]))
        if element.tag.rsplit("}", 1)[-1] == "OutOfProcessServer":
            declared.extend(relative_path(child.text or "") for child in element if child.tag.rsplit("}", 1)[-1] == "Path")
    if {p.casefold() for p in declared} != {p.casefold() for p in ENTRYPOINTS}:
        raise PayloadError("Declared executables differ from owned FileQuay app/server entrypoints: " + repr(declared))

    records = []
    for entry in ENTRYPOINTS:
        base, stem = PurePosixPath(entry).parent, PurePosixPath(entry).stem
        require_x64(entry)
        for native in HOST_FILES[:-1]: require_x64(base / native)
        require(base / (stem + ".dll"))
        options = document(base / (stem + ".runtimeconfig.json")).get("runtimeOptions", {})
        if "framework" in options or "frameworks" in options:
            raise PayloadError("Entrypoint is framework-dependent: " + entry)
        frameworks = {item["name"]: item["version"] for item in options.get("includedFrameworks", [])}
        required_frameworks = ["Microsoft.NETCore.App"] + (["Microsoft.WindowsDesktop.App"] if entry == "FolderSail.exe" else [])
        for name in required_frameworks:
            if frameworks.get(name) != runtime_version:
                raise PayloadError("Wrong or missing runtime version for " + entry + ": " + name + " must be " + runtime_version)
        deps = document(base / (stem + ".deps.json"))
        target_name = deps.get("runtimeTarget", {}).get("name", "")
        if not target_name.endswith("/win-x64"): raise PayloadError("Dependency manifest is not win-x64: " + entry)
        target = deps.get("targets", {}).get(target_name, {})
        for name in required_frameworks:
            expected = "runtimepack." + name + ".Runtime.win-x64/" + runtime_version
            if expected not in target: raise PayloadError("Missing exact runtime pack " + expected + " for " + entry)
        assets = set()
        for library in target.values():
            for category in ("runtime", "native", "resources"):
                for asset, metadata in library.get(category, {}).items():
                    asset = relative_path(asset)
                    if PurePosixPath(asset).name == "_._": continue
                    relative = PurePosixPath(asset).name
                    if category == "resources":
                        culture = metadata.get("locale")
                        if not culture: raise PayloadError("Resource has no locale: " + asset)
                        relative = relative_path(culture + "/" + relative)
                    require(base / relative); assets.add(str(base / relative))
        require(base / "Licenses/DotNetRuntime/LICENSE.TXT")
        require(base / "Licenses/DotNetRuntime/THIRD-PARTY-NOTICES.TXT")
        if entry == "FolderSail.exe": require("Licenses/WindowsDesktop/LICENSE")
        records.append({"path": entry, "frameworks": frameworks, "dependency_assets_checked": len(assets)})
    dependencies = declared_frameworks(manifest)
    artifact_validation = match_framework_archives(manifest, dependency_directory) if dependency_directory is not None else None
    return {"entrypoints": records, "runtime_version": runtime_version, "architecture": "x64", "declared_msix_dependencies": dependencies, "framework_artifact_validation": artifact_validation, "payload_inspection_passed": True, "startup_verified": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package-root", type=Path)
    parser.add_argument("--inventory", type=Path)
    parser.add_argument("--main-package", type=Path)
    parser.add_argument("--dependency-directory", type=Path)
    parser.add_argument("--runtime-version", default="10.0.12")
    args = parser.parse_args()
    try:
        if args.inventory:
            verify_required_names([entry["path"] for entry in json.loads(args.inventory.read_text())])
            result = {"required_names_present": True, "payload_inspection_passed": False, "startup_verified": False}
        elif args.main_package:
            if not args.dependency_directory: parser.error("--dependency-directory is required with --main-package")
            result = match_framework_archives(archive_manifest(args.main_package), args.dependency_directory)
        elif args.package_root: result = verify(args.package_root, args.runtime_version, args.dependency_directory)
        else: parser.error("--package-root or --inventory is required")
        print(json.dumps(result, indent=2)); return 0
    except (PayloadError, OSError, ET.ParseError, KeyError, TypeError, zipfile.BadZipFile) as error:
        print(json.dumps({"payload_inspection_passed": False, "error": str(error), "startup_verified": False}, indent=2)); return 1


if __name__ == "__main__": raise SystemExit(main())
