#!/usr/bin/env python3
"""Adds the NookiOS app target to Nook.xcodeproj. Idempotent: exits if the target exists."""
import re, sys, pathlib

P = pathlib.Path(__file__).resolve().parent.parent / "Nook.xcodeproj/project.pbxproj"
s = P.read_text()
if "NookiOS" in s:
    print("NookiOS target already present"); sys.exit(0)

def oid(n): return f"1050000000000000000{n:05d}"

TARGET, GROUP, SOURCES, FRAMEWORKS, RESOURCES = oid(1), oid(2), oid(3), oid(4), oid(5)
CONFLIST, DEBUG, RELEASE, PRODUCT = oid(6), oid(7), oid(8), oid(9)
PACKAGES = ["NookTabsCore", "NookSettings", "NookDesign", "NookBlocker", "NookTweaks", "NookWeb", "NookUI"]
dep_ids = {p: oid(100 + i) for i, p in enumerate(PACKAGES)}       # XCSwiftPackageProductDependency
file_ids = {p: oid(200 + i) for i, p in enumerate(PACKAGES)}      # PBXBuildFile

def insert_before(marker, text):
    global s
    assert s.count(marker) == 1, marker
    s = s.replace(marker, text + marker)

# PBXBuildFile entries for the package products
insert_before("/* End PBXBuildFile section */", "".join(
    f"\t\t{file_ids[p]} /* {p} in Frameworks */ = {{isa = PBXBuildFile; productRef = {dep_ids[p]} /* {p} */; }};\n"
    for p in PACKAGES))

# Product file reference
insert_before("/* End PBXFileReference section */",
    f"\t\t{PRODUCT} /* NookiOS.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = NookiOS.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n")

# Synchronized root group for NookiOS/. Info.plist is processed through INFOPLIST_FILE, so it
# must not also be copied as a resource.
EXC = oid(10)
insert_before("/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */",
    f"\t\t{EXC} /* Exceptions for \"NookiOS\" folder in \"NookiOS\" target */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;\n\t\t\tmembershipExceptions = (\n\t\t\t\tInfo.plist,\n\t\t\t);\n\t\t\ttarget = {TARGET} /* NookiOS */;\n\t\t}};\n")
insert_before("/* End PBXFileSystemSynchronizedRootGroup section */",
    f"\t\t{GROUP} /* NookiOS */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n\t\t\texceptions = (\n\t\t\t\t{EXC} /* Exceptions for \"NookiOS\" folder in \"NookiOS\" target */,\n\t\t\t);\n\t\t\tpath = NookiOS;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")

# Build phases
insert_before("/* End PBXFrameworksBuildPhase section */",
    f"\t\t{FRAMEWORKS} /* Frameworks */ = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n"
    + "".join(f"\t\t\t\t{file_ids[p]} /* {p} in Frameworks */,\n" for p in PACKAGES)
    + "\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n")
insert_before("/* End PBXSourcesBuildPhase section */",
    f"\t\t{SOURCES} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
insert_before("/* End PBXResourcesBuildPhase section */",
    f"\t\t{RESOURCES} /* Resources */ = {{\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")

# Native target
insert_before("/* End PBXNativeTarget section */", f"""\t\t{TARGET} /* NookiOS */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {CONFLIST} /* Build configuration list for PBXNativeTarget "NookiOS" */;
\t\t\tbuildPhases = (
\t\t\t\t{SOURCES} /* Sources */,
\t\t\t\t{FRAMEWORKS} /* Frameworks */,
\t\t\t\t{RESOURCES} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tfileSystemSynchronizedGroups = (
\t\t\t\t{GROUP} /* NookiOS */,
\t\t\t);
\t\t\tname = NookiOS;
\t\t\tpackageProductDependencies = (
""" + "".join(f"\t\t\t\t{dep_ids[p]} /* {p} */,\n" for p in PACKAGES) + f"""\t\t\t);
\t\t\tproductName = NookiOS;
\t\t\tproductReference = {PRODUCT} /* NookiOS.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
""")

# Register the target and the group with the project
old_targets = "\t\t\ttargets = (\n\t\t\t\t7F8340FB2E37F39400674A5D /* Nook */,\n"
assert s.count(old_targets) == 1, "targets list"
s = s.replace(old_targets, old_targets + f"\t\t\t\t{TARGET} /* NookiOS */,\n", 1)
m = re.search(r"(\t\t7F8340F32E37F39400674A5D = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n)", s)
assert m, "main group"
s = s[:m.end()] + f"\t\t\t\t{GROUP} /* NookiOS */,\n" + s[m.end():]
m = re.search(r"(\t\t7F8340FD2E37F39400674A5D /\* Products \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n)", s)
assert m, "products group"
s = s[:m.end()] + f"\t\t\t\t{PRODUCT} /* NookiOS.app */,\n" + s[m.end():]

# Package product dependencies (local packages: no package reference needed)
insert_before("/* End XCSwiftPackageProductDependency section */", "".join(
    f"\t\t{dep_ids[p]} /* {p} */ = {{\n\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tproductName = {p};\n\t\t}};\n"
    for p in PACKAGES))

# Build configurations
def config(oid_, name, extra):
    return f"""\t\t{oid_} /* {name} */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = NookiOS/NookiOS.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\t"EXCLUDED_ARCHS[sdk=iphonesimulator*]" = x86_64;
\t\t\t\tDEVELOPMENT_TEAM = ZHB786H6YN;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = NookiOS/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = Nook;
\t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 26.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 0.1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.gstudios.nook;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
{extra}\t\t\t}};
\t\t\tname = {name};
\t\t}};
"""
insert_before("/* End XCBuildConfiguration section */",
    config(DEBUG, "Debug", "\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";\n")
    + config(RELEASE, "Release", "\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;\n"))
insert_before("/* End XCConfigurationList section */", f"""\t\t{CONFLIST} /* Build configuration list for PBXNativeTarget "NookiOS" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{DEBUG} /* Debug */,
\t\t\t\t{RELEASE} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
""")
P.write_text(s)
print("NookiOS target added")
