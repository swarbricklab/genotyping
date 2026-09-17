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

Thermo Fisher publishes **only the current release**. At the time of writing
that is 2.12.0, which is the default here.

> **The manuscript run used APT 2.10.0, which can no longer be downloaded.**
> Building from this Dockerfile gives you 2.12.0, not a reproduction of that
> run. There is no way to rebuild 2.10.x from a Thermo Fisher URL; if you need
> it, you need an archived copy of the original zip.

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

```bash
docker build -t apt:2.12.0 containers/apt
```

To pin a different version, override both the version and its checksum:

```bash
docker build -t apt:2.11.6 \
  --build-arg APT_VERSION=2.11.6 \
  --build-arg APT_SHA256=<sha256 of that archive> \
  containers/apt
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

Snakemake converts `docker://` references to Singularity images on the fly
when run with `--use-singularity`, so a registry reference is all that is
needed. Because APT cannot be redistributed, that registry has to be one you
control — a private repository, or a registry internal to your institution.

If you cannot push to a registry, or you are on a cluster with Singularity but
no Docker (NCI Gadi, for example), export the image you built and convert it
once, then point `containers.apt` at the resulting file:

```bash
docker save apt:2.12.0 -o apt-2.12.0.tar
singularity build apt-2.12.0.sif docker-archive://apt-2.12.0.tar
```

```yaml
containers:
  apt: "containers/apt-2.12.0.sif"
```

`containers.apt` accepts either form.

If you omit `containers.apt`, the workflow falls back to the image used for our
published runs. That repository is **private**, so the fallback will fail to
pull for anyone outside the lab — by design, since we cannot redistribute APT.
The fallback exists so that existing dataset configs keep resolving to the
exact image their results came from. If you see an authentication or
"failed to get checksum" error from `singularity pull` on the first APT rule,
you have not set `containers.apt`.
