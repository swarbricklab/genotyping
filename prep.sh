#! /bin/bash

# Prepare the local dependencies that cannot be fetched by the workflow itself.
#
# At present that means the APT container image. APT is proprietary and cannot
# be redistributed with this workflow (see containers/apt/README.md), so the
# image has to be produced on the machine that will run the workflow.
#
# Usage:
#   ./prep.sh --configfile config/genotyping/config.yaml [options]
#
# Options:
#   --configfile PATH   Config file to read containers.apt from. Required
#                       unless --target is given.
#   --target PATH       Write the image here instead of the path in the config.
#   --from SOURCE       Where to get the image from. One of:
#                         docker://REF        pull from a registry
#                         PATH/TO/image.tar   a `docker save` archive
#                         dockerfile          build containers/apt (needs docker)
#                       Default: dockerfile.
#   --apt-version VER   APT version to build (default 2.12.0). dockerfile only.
#   --apt-sha256 SUM    Checksum for that version. Required if --apt-version is
#                       given, since the recorded default only matches 2.12.0.
#   --force             Rebuild even if the target already exists.
#
# Paths are interpreted relative to the current directory, which is how
# Snakemake resolves the value of containers.apt as well. Run this from the
# top of the super-project, the same place you run run_mod.sh.

set -euo pipefail

configfile=""
target=""
source_spec="dockerfile"
apt_version=""
apt_sha256=""
force="false"

# The Dockerfile lives next to this script, so the workflow can be installed as
# a submodule at any depth without the caller having to know where.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dockerfile_dir="$here/containers/apt"

die() { echo "ERROR: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --configfile)  configfile="${2:-}"; shift 2 ;;
        --target)      target="${2:-}"; shift 2 ;;
        --from)        source_spec="${2:-}"; shift 2 ;;
        --apt-version) apt_version="${2:-}"; shift 2 ;;
        --apt-sha256)  apt_sha256="${2:-}"; shift 2 ;;
        --force)       force="true"; shift ;;
        -h|--help)     sed -n '3,28p' "${BASH_SOURCE[0]}" | cut -c 3-; exit 0 ;;
        *)             die "unknown argument: $1" ;;
    esac
done

if [[ -n "$apt_version" && -z "$apt_sha256" ]]; then
    die "--apt-version requires --apt-sha256: the checksum recorded in the Dockerfile only matches its default version."
fi

if [[ "$(hostname)" == *"nci"* ]]; then
    module load singularity
fi

command -v singularity > /dev/null \
    || die "singularity not found. It is needed to build and to run the image."

# Work out where the image has to end up. Reading it from the config means
# there is one source of truth: whatever the workflow will look for.
if [[ -z "$target" ]]; then
    [[ -n "$configfile" ]] || die "give either --configfile or --target (see --help)."
    [[ -f "$configfile" ]] || die "config file not found: $configfile"

    # yq is only needed to read the config, so only require the environment
    # that provides it when a config was actually given.
    if ! command -v yq > /dev/null; then
        eval "$(conda shell.bash hook)"
        conda activate snakemake_7.32.4
    fi

    target="$(yq -r '.containers.apt // ""' "$configfile")"
    [[ "$target" == "null" ]] && target=""

    [[ -n "$target" ]] \
        || die "containers.apt is not set in $configfile. Set it to the path the image should live at, or pass --target."
fi

# A registry reference is resolved by Snakemake at run time, so there is
# nothing for us to place on disk -- just confirm it can be pulled.
if [[ "$target" == *"://"* ]]; then
    echo "containers.apt is a registry reference: $target"
    echo "Nothing to place on disk. Checking that it can be pulled."
    # This also populates the singularity layer cache, which makes Snakemake's
    # own pull cheaper -- but not free: Snakemake keeps its images under its
    # singularity-prefix, named by a hash of the URI, and will still create
    # that copy on the first run.
    singularity exec "$target" true \
        || die "could not pull $target. If it is a private repository, log in first (singularity remote login), or build a local image instead and point containers.apt at the file."
    echo "OK: $target is pullable."
    exit 0
fi

if [[ -e "$target" && "$force" != "true" ]]; then
    echo "$target already exists. Nothing to do (use --force to rebuild)."
    exit 0
fi

mkdir -p "$(dirname "$target")"

# Builds unpack the whole image into a temporary directory, so send that
# somewhere with room and with exec permitted rather than a small /tmp.
export SINGULARITY_TMPDIR="${SINGULARITY_TMPDIR:-${TMPDIR:-/tmp}}"
mkdir -p "$SINGULARITY_TMPDIR"

# Build into a temporary file and move it into place only on success, so an
# interrupted run cannot leave a half-written image that later looks complete.
tmp_sif="$(mktemp -u "$(dirname "$target")/.$(basename "$target").XXXXXX")"
cleanup() { rm -f "$tmp_sif"; }
trap cleanup EXIT

case "$source_spec" in
    docker://*)
        echo "Building $target from $source_spec"
        singularity build "$tmp_sif" "$source_spec"
        ;;

    *.tar)
        [[ -f "$source_spec" ]] || die "archive not found: $source_spec"
        echo "Building $target from docker archive $source_spec"
        singularity build "$tmp_sif" "docker-archive://$source_spec"
        ;;

    dockerfile)
        docker_cmd=""
        for c in docker podman; do
            if command -v "$c" > /dev/null; then docker_cmd="$c"; break; fi
        done

        [[ -n "$docker_cmd" ]] || die "$(cat <<EOF
no docker or podman found, so the image cannot be built from the Dockerfile here.
This is the normal situation on an HPC login node -- NCI Gadi has singularity
but no docker, and singularity cannot consume a Dockerfile.

Build the image on a machine that does have docker:

    docker build -t apt:2.12.0 $dockerfile_dir

then either push it to a registry you control and re-run with

    $0 --from docker://your-registry/apt:2.12.0 ...

or copy the saved archive across and convert it here:

    docker save apt:2.12.0 -o apt-2.12.0.tar    # on the machine with docker
    $0 --from apt-2.12.0.tar ...                # here

APT cannot be redistributed, so any registry you use has to be your own.
EOF
)"

        tag="apt:${apt_version:-2.12.0}"
        build_args=()
        if [[ -n "$apt_version" ]]; then
            build_args+=(--build-arg "APT_VERSION=$apt_version")
            build_args+=(--build-arg "APT_SHA256=$apt_sha256")
        fi

        echo "Building $tag with $docker_cmd from $dockerfile_dir"
        "$docker_cmd" build -t "$tag" "${build_args[@]}" "$dockerfile_dir"

        # Snakemake only ever runs containers through singularity, even for
        # docker:// references, so a local docker image is not directly usable
        # and has to be converted.
        archive="$(mktemp -u "$SINGULARITY_TMPDIR/apt-XXXXXX.tar")"
        echo "Exporting $tag and converting to a Singularity image"
        "$docker_cmd" save "$tag" -o "$archive"
        singularity build "$tmp_sif" "docker-archive://$archive"
        rm -f "$archive"
        ;;

    *)
        die "unrecognised --from value: $source_spec (expected docker://REF, a .tar archive, or 'dockerfile')"
        ;;
esac

# Confirm the image actually provides the tools the rules call, rather than
# just that a file was produced. Do this while it is still a temporary file:
# if it is moved into place first, a failed check leaves a broken image that
# the "already exists" test above would happily reuse on the next run.
#
# apt-genotype-axiom writes a log file into the working directory, so run the
# probe somewhere disposable.
echo
echo "Verifying the image"
abs_tmp="$(cd "$(dirname "$tmp_sif")" && pwd)/$(basename "$tmp_sif")"
probe_dir="$(mktemp -d)"
version="$(cd "$probe_dir" && singularity exec "$abs_tmp" apt-genotype-axiom --version 2>&1 \
    | grep -m1 "Version:" || true)"
rm -rf "$probe_dir"

[[ -n "$version" ]] \
    || die "the image was built but apt-genotype-axiom did not report a version, so it does not appear to contain APT. Nothing has been written to $target."

mv "$tmp_sif" "$target"
trap - EXIT

echo "  APT reports: ${version#*Version: }"
echo
echo "Done. containers.apt should be set to: $target"
