#! /bin/bash

# Prepare the local dependencies that cannot be fetched by the workflow itself,
# because they are supplied by Thermo Fisher under terms that do not let us
# redistribute them: the APT container image, and the Axiom array library and
# annotation files.
#
# Usage:
#   ./prep.sh --configfile config/genotyping/config.yaml [--what all] [options]
#
# Options:
#   --what STAGE        What to prepare: container, resources, or all.
#                       Default: container.
#   --configfile PATH   Config file to read paths from. Required unless the
#                       relevant --target/--resources-dir is given.
#   --force             Redo work even if the outputs already look complete.
#
# container stage:
#   --target PATH       Write the image here instead of the path in the config
#                       (containers.apt).
#   --from SOURCE       Where to get the image from. One of:
#                         docker://REF        pull from a registry
#                         PATH/TO/image.tar   a `docker save` archive
#                         dockerfile          build containers/apt (needs docker)
#                       Default: dockerfile.
#   --apt-version VER   APT version to build (default 2.12.0). dockerfile only.
#                       prep.sh already knows the download URL and checksum for
#                       2.12.0 and for the manuscript's 2.10.0, so either builds
#                       with just this flag. For any other version also give
#                       --apt-url and --apt-sha256.
#   --apt-url URL       Download URL for that version's Linux x86 zip. Needed
#                       only for a version prep.sh does not already know: the URL
#                       is not derivable from the version number.
#   --apt-sha256 SUM    Expected sha256 of that zip. As for --apt-url.
#   --accept-eula       Confirm you accept the Thermo Fisher APT EULA (required
#                       to build from the Dockerfile; you are prompted if a
#                       terminal is attached and this is not given).
#
# resources stage:
#   --resources-dir DIR Write the array files here instead of the directory
#                       holding refs.apt.arg_file in the config.
#   --array TYPE        Array type. Only UKB is supported (see below).
#
# Paths are interpreted relative to the current directory, which is how
# Snakemake resolves these config values as well. Run this from the top of the
# super-project, the same place you run run_mod.sh.

set -euo pipefail

what="container"
configfile=""
target=""
source_spec="dockerfile"
apt_version=""
apt_url=""
apt_sha256=""
accept_eula="false"
resources_dir=""
array="UKB"
force="false"

# The Dockerfile and checksum manifest live next to this script, so the
# workflow can be installed as a submodule at any depth without the caller
# having to know where.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dockerfile_dir="$here/containers/apt"

die() { echo "ERROR: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --what)           what="${2:-}"; shift 2 ;;
        --configfile)     configfile="${2:-}"; shift 2 ;;
        --target)         target="${2:-}"; shift 2 ;;
        --from)           source_spec="${2:-}"; shift 2 ;;
        --apt-version)    apt_version="${2:-}"; shift 2 ;;
        --apt-url)        apt_url="${2:-}"; shift 2 ;;
        --apt-sha256)     apt_sha256="${2:-}"; shift 2 ;;
        --accept-eula)    accept_eula="true"; shift ;;
        --resources-dir)  resources_dir="${2:-}"; shift 2 ;;
        --array)          array="${2:-}"; shift 2 ;;
        --force)          force="true"; shift ;;
        -h|--help)        sed -n '3,46p' "${BASH_SOURCE[0]}" | cut -c 3-; exit 0 ;;
        *)                die "unknown argument: $1" ;;
    esac
done

case "$what" in
    container|resources|all) ;;
    *) die "--what must be container, resources or all (got: $what)" ;;
esac

# Resolve the download URL and checksum for a requested version. The URL is not
# a predictable function of the version -- Thermo Fisher keeps older releases at
# a different path -- so the versions we have built are recorded here rather
# than derived. With no version flag we pass nothing and let the Dockerfile use
# its own default; that keeps a single source of truth for the default version.
if [[ -n "$apt_version" || -n "$apt_url" ]]; then
    case "${apt_version:-2.12.0}" in
        2.12.0)
            apt_url="${apt_url:-https://downloads.thermofisher.com/APT/APT_2.12.0/apt_2.12.0_linux_64_x86_binaries.zip}"
            apt_sha256="${apt_sha256:-d715adbc0a14df71e42f14bf250d3c39718d7a6712e8b8b2127192715196bafe}"
            ;;
        2.10.0)
            apt_url="${apt_url:-https://downloads.thermofisher.com/Affymetrix_Softwares/APT_2.10.0/apt-2.10.0-x86_64-intel-linux.zip}"
            apt_sha256="${apt_sha256:-c5503f95c1c773a319562cac170d24f1e771be7fec39b88f3f72734c9952f9d9}"
            ;;
    esac
    [[ -n "$apt_url"    ]] || die "APT ${apt_version} is not a version prep.sh has a URL for; give --apt-url as well (see containers/apt/README.md)."
    [[ -n "$apt_sha256" ]] || die "APT ${apt_version} needs its checksum; give --apt-sha256 as well (see containers/apt/README.md)."
fi

# Read one dotted key out of the config file. yq is only needed for this, so
# only require the environment that provides it when a config was given.
config_value() {
    local key="$1"
    [[ -f "$configfile" ]] || die "config file not found: $configfile"
    if ! command -v yq > /dev/null; then
        eval "$(conda shell.bash hook)"
        conda activate snakemake_7.32.4
    fi
    local v
    v="$(yq -r "$key // \"\"" "$configfile")"
    [[ "$v" == "null" ]] && v=""
    printf '%s' "$v"
}


prep_container() {
    command -v singularity > /dev/null \
        || die "singularity not found. It is needed to build and to run the image."

    # Work out where the image has to end up. Reading it from the config means
    # there is one source of truth: whatever the workflow will look for.
    if [[ -z "$target" ]]; then
        [[ -n "$configfile" ]] || die "give either --configfile or --target (see --help)."
        target="$(config_value '.containers.apt')"
        [[ -n "$target" ]] \
            || die "containers.apt is not set in $configfile. Set it to the path the image should live at, or pass --target."
    fi

    # A registry reference is resolved by Snakemake at run time, so there is
    # nothing for us to place on disk -- just confirm it can be pulled.
    if [[ "$target" == *"://"* ]]; then
        echo "containers.apt is a registry reference: $target"
        echo "Nothing to place on disk. Checking that it can be pulled."
        # This also populates the singularity layer cache, which makes
        # Snakemake's own pull cheaper -- but not free: Snakemake keeps its
        # images under its singularity-prefix, named by a hash of the URI, and
        # will still create that copy on the first run.
        singularity exec "$target" true \
            || die "could not pull $target. If it is a private repository, log in first (singularity remote login), or build a local image instead and point containers.apt at the file."
        echo "OK: $target is pullable."
        return 0
    fi

    if [[ -e "$target" && "$force" != "true" ]]; then
        echo "$target already exists. Nothing to do (use --force to rebuild)."
        return 0
    fi

    mkdir -p "$(dirname "$target")"

    # Builds unpack the whole image into a temporary directory, so send that
    # somewhere with room and with exec permitted rather than a small /tmp.
    export SINGULARITY_TMPDIR="${SINGULARITY_TMPDIR:-${TMPDIR:-/tmp}}"
    mkdir -p "$SINGULARITY_TMPDIR"

    # Build into a temporary file and move it into place only on success, so an
    # interrupted run cannot leave a half-written image that later looks complete.
    local tmp_sif
    tmp_sif="$(mktemp -u "$(dirname "$target")/.$(basename "$target").XXXXXX")"
    # shellcheck disable=SC2064
    trap "rm -f '$tmp_sif'" RETURN

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
            local docker_cmd=""
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

            local tag="apt:${apt_version:-2.12.0}"
            local build_args=()
            if [[ -n "$apt_version" || -n "$apt_url" ]]; then
                build_args+=(--build-arg "APT_VERSION=${apt_version:-2.12.0}")
                build_args+=(--build-arg "APT_URL=$apt_url")
                build_args+=(--build-arg "APT_SHA256=$apt_sha256")
            fi

            # APT is proprietary; building downloads it from Thermo Fisher under
            # their EULA. Require conscious acceptance (the Dockerfile refuses to
            # build without it). containers/apt/build.sh is the friendlier route.
            if [[ "$accept_eula" != "true" ]]; then
                if [[ -t 0 ]]; then
                    echo "APT is proprietary Thermo Fisher software under an End User License"
                    echo "Agreement; building downloads it from Thermo Fisher. See"
                    echo "containers/apt/README.md."
                    read -r -p "Type 'yes' to accept the Thermo Fisher EULA: " reply
                    [[ "$reply" == "yes" ]] \
                        || die "EULA not accepted, so nothing was built. Re-run with --accept-eula, or use containers/apt/build.sh."
                else
                    die "building from the Dockerfile requires accepting the Thermo Fisher EULA: re-run with --accept-eula (see containers/apt/README.md), or use containers/apt/build.sh."
                fi
            fi
            build_args+=(--build-arg "ACCEPT_THERMOFISHER_EULA=yes")

            echo "Building $tag with $docker_cmd from $dockerfile_dir"
            "$docker_cmd" build -t "$tag" "${build_args[@]}" "$dockerfile_dir"

            # Snakemake only ever runs containers through singularity, even for
            # docker:// references, so a local docker image is not directly
            # usable and has to be converted.
            local archive
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
    # just that a file was produced. Do this while it is still a temporary
    # file: if it is moved into place first, a failed check leaves a broken
    # image that the "already exists" test above would happily reuse.
    #
    # apt-genotype-axiom writes a log file into the working directory, so run
    # the probe somewhere disposable.
    echo
    echo "Verifying the image"
    local abs_tmp probe_dir version
    abs_tmp="$(cd "$(dirname "$tmp_sif")" && pwd)/$(basename "$tmp_sif")"
    probe_dir="$(mktemp -d)"
    version="$(cd "$probe_dir" && singularity exec "$abs_tmp" apt-genotype-axiom --version 2>&1 \
        | grep -m1 "Version:" || true)"
    rm -rf "$probe_dir"

    [[ -n "$version" ]] \
        || die "the image was built but apt-genotype-axiom did not report a version, so it does not appear to contain APT. Nothing has been written to $target."

    mv "$tmp_sif" "$target"

    echo "  APT reports: ${version#*Version: }"
    echo
    echo "Done. containers.apt is set to: $target"
}


prep_resources() {
    # Only the UK Biobank array is wired up. PMDA needs more than a different
    # set of downloads: it has no ps2snp_map.ps (the equivalent is
    # ps2multisnp_map.ps) and a different annotation build, and apt.smk does
    # not handle either yet -- see the TODO in workflow/rules/apt.smk.
    [[ "$array" == "UKB" ]] \
        || die "only --array UKB is supported. The workflow does not yet handle $array (see the TODO in workflow/rules/apt.smk)."

    local manifest="$here/resources/axiom_ukb_wcsg_r5.sha256"
    [[ -f "$manifest" ]] || die "checksum manifest not found: $manifest"

    if [[ -z "$resources_dir" ]]; then
        [[ -n "$configfile" ]] \
            || die "give either --configfile or --resources-dir (see --help)."
        local arg_file
        arg_file="$(config_value '.refs.apt.arg_file')"
        [[ -n "$arg_file" ]] \
            || die "refs.apt.arg_file is not set in $configfile, so the directory for these files cannot be determined. Pass --resources-dir instead."
        # APT resolves the other library files by bare filename against
        # --analysis-files-path, which apt.smk sets to this directory, so they
        # all have to land together.
        resources_dir="$(dirname "$arg_file")"
    fi

    mkdir -p "$resources_dir"

    # Thermo Fisher publishes no checksums, so these are ones we recorded. They
    # are verified byte-identical to the files used for the published runs.
    if [[ "$force" != "true" ]] && (cd "$resources_dir" && sha256sum -c --quiet "$manifest" > /dev/null 2>&1); then
        echo "$resources_dir already holds all the array files, and they match the recorded checksums."
        echo "Nothing to do (use --force to re-download)."
        return 0
    fi

    cat <<EOF
Downloading Axiom UK Biobank (Axiom_UKB_WCSG) release r5 library files and the
na35 annotation database into $resources_dir

These are supplied by Thermo Fisher. They are not redistributable, so they are
fetched from the vendor rather than shipped with this workflow. About 480 MB of
downloads expanding to roughly 2.5 GB, most of it the annotation database.

EOF

    local base="https://www.affymetrix.com/api/downloads/lf/genotyping/Axiom_UKB_WCSG/r5"
    local name
    # Read the filenames from the manifest so there is one list, not two.
    while read -r _ name; do
        [[ -n "$name" ]] || continue
        # Match the manifest line on an exact filename, so that one name being
        # a suffix of another could not select the wrong checksum.
        if [[ "$force" != "true" && -f "$resources_dir/$name" ]] \
           && (cd "$resources_dir" && awk -v n="$name" '$2 == n' "$manifest" | sha256sum -c --quiet - > /dev/null 2>&1); then
            echo "  have    $name"
            continue
        fi
        echo "  fetch   $name"
        # Each archive is flat: one file at its root, no directory prefix.
        curl -fsSL --retry 3 -o "$resources_dir/$name.zip" "$base/$name.zip" \
            || die "could not download $name.zip from $base. See containers/apt/README.md for the alternative routes if this host has been retired."
        unzip -o -q -j "$resources_dir/$name.zip" -d "$resources_dir" \
            || die "could not unpack $resources_dir/$name.zip"
        rm -f "$resources_dir/$name.zip"
    done < "$manifest"

    echo
    echo "Verifying checksums"
    (cd "$resources_dir" && sha256sum -c --quiet "$manifest") \
        || die "downloaded files do not match the recorded checksums in $manifest. Thermo Fisher may have re-released these files; do not use them for a run you intend to compare against published results without checking why."

    echo "  all files match"
    echo
    echo "Done. refs.apt paths should resolve under: $resources_dir"
}


if [[ "$what" == "container" || "$what" == "all" ]]; then
    prep_container
fi

if [[ "$what" == "resources" || "$what" == "all" ]]; then
    [[ "$what" == "all" ]] && echo
    prep_resources
elif [[ "$what" == "container" ]]; then
    echo "(to also fetch the Axiom array files, re-run with --what resources)"
fi
