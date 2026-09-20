#! /bin/bash

# Build the APT container image and save it as a tarball ready to copy to the
# machine that will run the workflow (e.g. NCI Gadi, which has Singularity but
# no Docker).
#
# APT is proprietary Thermo Fisher software under an End User License Agreement
# (see README.md and the Dockerfile header). This script makes you accept that
# EULA before it builds, and passes the acceptance through to the Dockerfile,
# which refuses to build without it.
#
# Usage:
#   ./containers/apt/build.sh [options]
#
# Options:
#   --apt-version VER  APT version to build (default 2.12.0). Knows the URL and
#                      checksum for 2.12.0 and the manuscript's 2.10.0; for any
#                      other version also give --apt-url and --apt-sha256.
#   --apt-url URL      Download URL for that version's Linux x86 zip.
#   --apt-sha256 SUM   Expected sha256 of that zip.
#   --platform PLAT    Build platform (default linux/amd64). The APT binaries
#                      are x86-64 Linux, so on Apple Silicon this must stay
#                      linux/amd64 (Docker runs it under emulation).
#   --tag TAG          Image tag (default apt:<version>).
#   --tar PATH         Tarball to write (default apt-<version>.tar). Empty ("")
#                      skips the save and leaves the image in the local daemon.
#   --yes              Accept the EULA without the interactive prompt.
#
# After it finishes, copy the tarball across and place it with:
#   ./prep.sh --from apt-<version>.tar --configfile <your config>

set -euo pipefail

apt_version="2.12.0"
apt_url=""
apt_sha256=""
platform="linux/amd64"
tag=""
tar_out="__default__"
assume_yes="false"
docker_cmd=""

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
die() { echo "ERROR: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apt-version) apt_version="${2:-}"; shift 2 ;;
        --apt-url)     apt_url="${2:-}"; shift 2 ;;
        --apt-sha256)  apt_sha256="${2:-}"; shift 2 ;;
        --platform)    platform="${2:-}"; shift 2 ;;
        --tag)         tag="${2:-}"; shift 2 ;;
        --tar)         tar_out="${2:-}"; shift 2 ;;
        --yes)         assume_yes="true"; shift ;;
        -h|--help)     sed -n '3,33p' "${BASH_SOURCE[0]}" | cut -c 3-; exit 0 ;;
        *)             die "unknown argument: $1" ;;
    esac
done

# Resolve the download URL and checksum for versions we know (see prep.sh for
# the same table). The URL is not a predictable function of the version.
case "$apt_version" in
    2.12.0)
        apt_url="${apt_url:-https://downloads.thermofisher.com/APT/APT_2.12.0/apt_2.12.0_linux_64_x86_binaries.zip}"
        apt_sha256="${apt_sha256:-d715adbc0a14df71e42f14bf250d3c39718d7a6712e8b8b2127192715196bafe}"
        ;;
    2.10.0)
        apt_url="${apt_url:-https://downloads.thermofisher.com/Affymetrix_Softwares/APT_2.10.0/apt-2.10.0-x86_64-intel-linux.zip}"
        apt_sha256="${apt_sha256:-c5503f95c1c773a319562cac170d24f1e771be7fec39b88f3f72734c9952f9d9}"
        ;;
esac
[[ -n "$apt_url"    ]] || die "APT $apt_version is not a version build.sh has a URL for; pass --apt-url (and --apt-sha256)."
[[ -n "$apt_sha256" ]] || die "APT $apt_version needs its checksum; pass --apt-sha256."

for c in docker podman; do
    if command -v "$c" > /dev/null; then docker_cmd="$c"; break; fi
done
[[ -n "$docker_cmd" ]] || die "no docker or podman found. This script builds an image, which needs one of them."

[[ -n "$tag" ]] || tag="apt:$apt_version"
[[ "$tar_out" == "__default__" ]] && tar_out="apt-$apt_version.tar"

cat <<EOF

Analysis Power Tools (APT) $apt_version is proprietary software distributed by
Thermo Fisher Scientific under an End User License Agreement. Building this
image downloads APT from Thermo Fisher:

  $apt_url

The EULA grants a non-transferable, non-sublicensable licence to use the
software for research, on computers you own or control, and prohibits
redistributing it. See containers/apt/README.md for the full background.

  *** Do not push the resulting image to a public registry. ***

EOF

if [[ "$assume_yes" != "true" ]]; then
    read -r -p "Type 'yes' to confirm you accept the Thermo Fisher EULA and take responsibility for your own relationship with Thermo Fisher: " reply
    [[ "$reply" == "yes" ]] || die "EULA not accepted (you typed '${reply:-}'). Nothing was built."
fi

echo
echo "Building $tag for $platform with $docker_cmd"
"$docker_cmd" build \
    --platform "$platform" \
    --build-arg "ACCEPT_THERMOFISHER_EULA=yes" \
    --build-arg "APT_VERSION=$apt_version" \
    --build-arg "APT_URL=$apt_url" \
    --build-arg "APT_SHA256=$apt_sha256" \
    -t "$tag" "$here"

if [[ -n "$tar_out" ]]; then
    echo
    echo "Saving $tag to $tar_out"
    "$docker_cmd" save "$tag" -o "$tar_out"
    echo
    echo "Done. Copy $tar_out to the machine that runs the workflow, then:"
    echo "  ./prep.sh --from $tar_out --configfile <your config>"
else
    echo
    echo "Done. Image $tag is in the local $docker_cmd daemon (no tarball written)."
fi
