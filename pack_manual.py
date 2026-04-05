#!/usr/bin/env python3
"""
pack_manual.py  —  Cria o .deb final juntando um dylib compilado + vcamrootless
Uso após compilar o tweak com Theos:
    python3 pack_manual.py --dylib .theos/obj/arm64+arm64e/vcamoverlay.dylib

Ou se quiser empacotar só o vcamrootless original sem overlay:
    python3 pack_manual.py --only-vcam
"""
import argparse, lzma, tarfile, io, struct, os, sys, hashlib

TEMP_MOV_PATH = "/var/jb/var/mobile/Library/temp.mov"

def make_control_tar(control_text: str) -> bytes:
    buf = io.BytesIO()
    with lzma.open(buf, "w", format=lzma.FORMAT_XZ) as xzf:
        with tarfile.open(fileobj=xzf, mode="w") as tf:
            data = control_text.encode()
            ti = tarfile.TarInfo("./control")
            ti.size = len(data)
            tf.addfile(ti, io.BytesIO(data))
    return buf.getvalue()


def make_data_tar(files: list[tuple[str, bytes, int]]) -> bytes:
    """files = [(archive_path, content_bytes, mode)]"""
    buf = io.BytesIO()
    with lzma.open(buf, "w", format=lzma.FORMAT_XZ) as xzf:
        with tarfile.open(fileobj=xzf, mode="w") as tf:
            # Diretórios necessários
            dirs = set()
            for path, _, _ in files:
                parts = path.split("/")
                for i in range(1, len(parts)):
                    dirs.add("/".join(parts[:i]))
            for d in sorted(dirs):
                ti = tarfile.TarInfo("./" + d)
                ti.type = tarfile.DIRTYPE
                ti.mode = 0o755
                tf.addfile(ti)
            for path, content, mode in files:
                ti = tarfile.TarInfo("./" + path)
                ti.size = len(content)
                ti.mode = mode
                tf.addfile(ti, io.BytesIO(content))
    return buf.getvalue()


def ar_pack(parts: list[tuple[str, bytes]]) -> bytes:
    """Cria arquivo .ar (formato deb)"""
    result = b"!<arch>\n"
    for name, content in parts:
        name_field = name.encode().ljust(16)[:16]
        size_field = str(len(content)).encode().ljust(10)[:10]
        header = name_field + b"0           " + b"0     " + b"0     " + b"100644  " + size_field + b"`\n"
        result += header + content
        if len(content) % 2 == 1:
            result += b"\n"
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dylib", help="Path to compiled vcamoverlay.dylib")
    parser.add_argument("--only-vcam", action="store_true", help="Pack only vcamrootless")
    parser.add_argument("--out", default="VcamRootless_Overlay.deb")
    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    vendor_dir = os.path.join(script_dir, "vendor")

    # Carrega vcamrootless
    with open(os.path.join(vendor_dir, "vcamrootless.dylib"), "rb") as f:
        vcam_dylib = f.read()
    with open(os.path.join(vendor_dir, "vcamrootless.plist"), "rb") as f:
        vcam_plist = f.read()

    files = [
        ("var/jb/Library/MobileSubstrate/DynamicLibraries/vcamrootless.dylib", vcam_dylib, 0o755),
        ("var/jb/Library/MobileSubstrate/DynamicLibraries/vcamrootless.plist", vcam_plist, 0o644),
    ]

    if not args.only_vcam:
        if not args.dylib:
            # Tenta achar automaticamente
            candidates = [
                ".theos/obj/arm64+arm64e/vcamoverlay.dylib",
                ".theos/obj/vcamoverlay.dylib",
                "packages/vcamoverlay.dylib",
            ]
            for c in candidates:
                full = os.path.join(script_dir, c)
                if os.path.exists(full):
                    args.dylib = full
                    break
        if args.dylib and os.path.exists(args.dylib):
            with open(args.dylib, "rb") as f:
                overlay_dylib = f.read()
            overlay_plist_path = os.path.join(
                script_dir, "layout/var/jb/Library/MobileSubstrate/DynamicLibraries/vcamoverlay.plist"
            )
            with open(overlay_plist_path, "rb") as f:
                overlay_plist = f.read()
            files += [
                ("var/jb/Library/MobileSubstrate/DynamicLibraries/vcamoverlay.dylib", overlay_dylib, 0o755),
                ("var/jb/Library/MobileSubstrate/DynamicLibraries/vcamoverlay.plist", overlay_plist, 0o644),
            ]
            print(f"✓ Incluindo vcamoverlay.dylib ({len(overlay_dylib)//1024} KB)")
        else:
            print("⚠  vcamoverlay.dylib não encontrado — empacotando só o vcamrootless")

    control_text = f"""Package: com.vcam.rootless.overlay
Name: VcamRootless + Overlay
Version: 1.0.1
Architecture: iphoneos-arm64
Description: Virtual camera with LordVCAM-style overlay (volume+/- to toggle)
Section: Tweaks
Maintainer: dev
Depends: mobilesubstrate (>= 0.9.5000)
Installed-Size: {sum(len(c) for _, c, _ in files) // 1024}
"""

    debian_binary = b"2.0\n"
    control_tar = make_control_tar(control_text)
    data_tar = make_data_tar(files)

    deb = ar_pack([
        ("debian-binary", debian_binary),
        ("control.tar.xz", control_tar),
        ("data.tar.xz", data_tar),
    ])

    out_path = os.path.join(script_dir, args.out)
    with open(out_path, "wb") as f:
        f.write(deb)
    print(f"✅ Gerado: {out_path}  ({len(deb)//1024} KB)")


if __name__ == "__main__":
    main()
