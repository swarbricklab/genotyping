# APT container

`Dockerfile` builds a container image containing Thermo Fisher [Analysis Power
Tools](https://www.thermofisher.com/us/en/home/life-science/microarray-analysis/microarray-analysis-partners-programs/affymetrix-developers-network/affymetrix-power-tools.html)
(APT) and SNPolisher, used by the rules in `workflow/rules/apt.smk`.

It downloads APT from Thermo Fisher at build time, verifies it against a
recorded SHA-256, and fails the build if it does not match.

## Why you have to build this yourself

APT is proprietary. It is distributed under a Life Technologies Corporation
End User License Agreement, which ships inside the download as `EULA.docx`.
The EULA grants:

> a non-exclusive, non-transferable license, with no rights to sublicense, to
> install and/or use the Software only in object code (machine readable)
> format and only on single computers owned or controlled by you [...] for
> research use only.

and prohibits:

> copy, transfer [...] rent, modify, distribute, electronically transmit,
> lend, lease, use, create derivative works based on the Software or merge the
> Software [...] whether alone or combined with any other products.

Publishing an image that contains APT is therefore not something we can do on
your behalf, and **you should not push the image you build to a public
registry**. Building it locally is fine — you obtain APT from the vendor under
your own acceptance of their terms, which is the whole point of shipping a
recipe instead of an image.

Note that APT is *not* GPL, despite what several search results and mirrors
will tell you. That applies to the APT 1.x series. The 2.x downloads carry the
EULA above, ship no source, and the source repository referenced in the
binaries (`github.com/thermofisher/ma-alg-apt2-genotyping`) is private. The
2.12.0 archive still contains a stale `doc/readme.txt` describing "Version
1.20.5, Binary/Source distributions", which is where much of the confusion
comes from.

## Versions

The default is 2.12.0, the current release.

**The manuscript run used APT 2.10.0, and it is still downloadable** — Thermo
Fisher keeps older releases at a different path from the current one, so the URL
is not a predictable function of the version. `prep.sh` knows the URL and
checksum for both 2.12.0 and 2.10.0:

```bash
./prep.sh --configfile <your config file> --apt-version 2.10.0
```

To build it by hand, all three build-args have to be given together (the URL
cannot be derived from the version), plus the EULA acceptance (see Building
below); or just use `build.sh --apt-version 2.10.0`:

```bash
docker build -t apt:2.10.0 \
  --build-arg ACCEPT_THERMOFISHER_EULA=yes \
  --build-arg APT_VERSION=2.10.0 \
  --build-arg APT_URL=https://downloads.thermofisher.com/Affymetrix_Softwares/APT_2.10.0/apt-2.10.0-x86_64-intel-linux.zip \
  --build-arg APT_SHA256=c5503f95c1c773a319562cac170d24f1e771be7fec39b88f3f72734c9952f9d9 \
  containers/apt
```

The 2.10.0 archive nests its `bin/`, EULA and `licenses/` under a top-level
directory, where 2.12.0 has them at the archive root; the Dockerfile detects
either layout, so no other change is needed to switch versions.

Some history worth knowing, since it affects how you read the methods:

- The image this workflow used to pin, `swarbricklab/ctp-tools:apt-2.10.2`,
  was **mislabelled**. `apt-genotype-axiom` in it reports `2.10.0`, while
  `ps-metrics` and `ps-classification` report `2.10.2` and
  `apt-format-result` reports `2.10.2.2`. It was assembled by copying
  binaries from more than one APT release, and carried no record of which
  archives they came from.
- Mixed versions within a bundle are not unusual — Thermo Fisher's own
  official 2.12.0 archive ships `otv-caller` 2.11.6.

So when quoting a version, say which binary you mean. Genotypes are called by
`apt-genotype-axiom`.

## Building

### Accepting the EULA

Because building downloads APT from Thermo Fisher under their EULA, the build
**fails unless you confirm you accept it** by passing
`--build-arg ACCEPT_THERMOFISHER_EULA=yes`. This is a deliberate gate: it makes
acceptance a conscious act, so no one bundles APT by accident. By setting it you
confirm you have read and accept the EULA and take responsibility for your own
relationship with Thermo Fisher.

### With build.sh (recommended for a laptop)

[`build.sh`](build.sh) prompts you to accept the EULA, then builds and saves a
tarball ready to copy to the machine that runs the workflow. On an
Apple-Silicon Mac it sets `--platform linux/amd64` for you (the APT binaries are
x86-64, so a native arm64 build would not run):

```bash
./containers/apt/build.sh                     # defaults to 2.12.0
./containers/apt/build.sh --apt-version 2.10.0   # the manuscript version
```

This writes `apt-<version>.tar`; copy it across and place it with
`./prep.sh --from apt-<version>.tar --configfile <your config file>`.

### With prep.sh

[`prep.sh`](../../prep.sh) builds the image, converts it for Singularity if
needed, and places it wherever `containers.apt` points. It prompts for EULA
acceptance (or pass `--accept-eula`):

```bash
./prep.sh --configfile <your config file> --accept-eula
```

It is idempotent, and it verifies that APT actually runs inside the image before
putting it in place.

### By hand

```bash
docker build --build-arg ACCEPT_THERMOFISHER_EULA=yes -t apt:2.12.0 containers/apt
```

To pin a version other than the two prep.sh knows, override the version, its URL
and its checksum together (the URL is not derivable from the version):

```bash
docker build \
  --build-arg ACCEPT_THERMOFISHER_EULA=yes \
  --build-arg APT_VERSION=2.11.6 \
  --build-arg APT_URL=<download URL for that archive> \
  --build-arg APT_SHA256=<sha256 of that archive> \
  -t apt:2.11.6 containers/apt
```

The build runs `apt-genotype-axiom --version` as a test, so the real version
is recorded in the build log.

## Wiring it into the workflow

Set `containers.apt` in your config file to the image you built:

```yaml
containers:
  apt: "docker://your-registry/apt:2.12.0"
```

That one value is used by all five APT rules (`apt`, `ps_metrics`,
`ps_classification`, `otv_caller`, `make_vcf`).

Snakemake runs containers **only** through Singularity — there is no Docker
runtime path, even for a `docker://` reference. Such a reference is simply a URI
that Singularity knows how to fetch and convert, which it does on the fly under
`--use-singularity`. So a registry reference is all that is needed. Because APT
cannot be redistributed, that registry has to be one you control — a private
repository, or a registry internal to your institution.

`containers.apt` also accepts a local path:

```yaml
containers:
  apt: "containers/apt-2.12.0.sif"
```

Two consequences of everything going through Singularity are worth knowing:

- A local path has to be a **Singularity image file**. An image sitting in a
  local Docker daemon cannot be named by path, and a `docker save` tarball is
  not a SIF — pointing at one fails with `invalid SIF magic`. Convert it first.
- Relative paths are resolved against the directory you run Snakemake from
  (the top of the super-project), not against this module.

So if you cannot push to a registry, or you are on a cluster with Singularity
but no Docker (NCI Gadi, for example), convert the image once. `prep.sh` will do
this for you:

```bash
docker save apt:2.12.0 -o apt-2.12.0.tar    # on a machine with docker
./prep.sh --configfile <your config file> --from apt-2.12.0.tar
```

or by hand:

```bash
singularity build apt-2.12.0.sif docker-archive://apt-2.12.0.tar
```

Note that Snakemake does **not** check that a local path exists when it builds
the DAG, so a wrong path survives `--dry-run` and only fails when the first APT
rule runs. Running `prep.sh` first avoids that class of surprise.

If you omit `containers.apt`, the workflow falls back to the image used for our
published runs. That repository is **private**, so the fallback will fail to
pull for anyone outside the lab — by design, since we cannot redistribute APT.
The fallback exists so that existing dataset configs keep resolving to the
exact image their results came from. If you see an authentication or
"failed to get checksum" error from `singularity pull` on the first APT rule,
you have not set `containers.apt`.
