# Analysis Power Tools (APT) and SNPolisher, for the rules in
# workflow/rules/apt.smk.
#
# LICENSING -- READ BEFORE BUILDING OR SHARING THIS IMAGE
#
# APT is proprietary software, distributed by Life Technologies Corporation
# (Thermo Fisher Scientific) under an End User License Agreement. The EULA
# grants a "non-exclusive, non-transferable license, with no rights to
# sublicense" to use the software "only on single computers owned or
# controlled by you", "for research use only", and states that you "shall
# not copy, transfer [...] distribute, electronically transmit [...] or
# merge the Software [...] whether alone or combined with any other
# products".
#
# Building this image yourself is fine: you download APT from Thermo Fisher
# under your own acceptance of their terms. Publishing the result is not.
#
#   *** Do not push this image to a public registry. ***
#
# That is not a hypothetical caution. This workflow previously pinned a
# public image that bundled these binaries, which is exactly what the EULA
# prohibits. The point of this file is that the licensed party (you) obtains
# the software directly from the vendor, rather than receiving a copy from us.
#
# The download ships EULA.docx and a licenses/ directory covering third-party
# components; both are copied into the final image, because the EULA requires
# that end users receive those notices.
#
# VERSION
#
# The default is APT 2.12.0, the current release. To build a different
# version, override APT_VERSION, APT_URL and APT_SHA256 together: the download
# URL is not a predictable function of the version, so the version alone is not
# enough. prep.sh --apt-version knows the URLs for the versions we have used.
#
# The manuscript run used APT 2.10.0. Thermo Fisher still publishes it, at a
# different path from the current release (see APT_URL below and the README);
# it can be rebuilt from this file.
#
# The extraction copes with either archive layout: 2.12.0 unpacks bin/, the
# EULA and licenses/ at the archive root, while 2.10.0 nests them under a
# single top-level directory.
#
# USAGE
#
#   docker build -t apt:2.12.0 containers/apt
#
# then point the apt.smk rules at your own image or a local .sif built from
# it. See containers/apt/README.md.

ARG APT_VERSION=2.12.0

# ---------------------------------------------------------------------------
# Fetch and verify. Kept in a separate stage so that curl, unzip and the
# ~200 MB archive do not end up as layers in the final image.
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim AS fetch

ARG APT_VERSION
ARG APT_URL=https://downloads.thermofisher.com/APT/APT_${APT_VERSION}/apt_${APT_VERSION}_linux_64_x86_binaries.zip
# sha256 of apt_2.12.0_linux_64_x86_binaries.zip (205,220,602 bytes), verified
# against the published download. Override together with APT_VERSION and
# APT_URL. For 2.10.0 it is
# c5503f95c1c773a319562cac170d24f1e771be7fec39b88f3f72734c9952f9d9.
ARG APT_SHA256=d715adbc0a14df71e42f14bf250d3c39718d7a6712e8b8b2127192715196bafe

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip \
 && rm -rf /var/lib/apt/lists/*

# Fail the build rather than bake in an unverified archive. The known archive
# layouts differ (see VERSION above), so unpack to a scratch directory and
# locate the directory that actually contains bin/ -- that is the APT root,
# whether it sits at the archive root (2.12.0) or one level down (2.10.0). The
# EULA is normalised to a single name (2.10.0 ships EULA.DOCX, 2.12.0
# EULA.docx) so the final stage can COPY it by a fixed path.
RUN curl -fsSL -o /tmp/apt.zip "${APT_URL}" \
 && printf '%s  /tmp/apt.zip\n' "${APT_SHA256}" | sha256sum -c - \
 && unzip -q /tmp/apt.zip -d /tmp/unpack \
 && rm /tmp/apt.zip \
 && if [ -d /tmp/unpack/bin ]; then aptroot=/tmp/unpack; \
    else aptroot="$(dirname "$(find /tmp/unpack -mindepth 2 -maxdepth 2 -type d -name bin | head -1)")"; fi \
 && mkdir -p /opt/apt \
 && cp -a "$aptroot/bin" /opt/apt/bin \
 && cp -a "$aptroot/licenses" /opt/apt/licenses \
 && cp -a "$aptroot"/EULA.[dD][oO][cC][xX] /opt/apt/EULA.docx \
 && rm -rf /tmp/unpack \
 && chmod +x /opt/apt/bin/*

# ---------------------------------------------------------------------------
# Runtime. The APT binaries are statically linked, so nothing beyond a base
# filesystem is needed to run them.
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim

ARG APT_VERSION
LABEL org.opencontainers.image.title="Analysis Power Tools (APT)" \
      org.opencontainers.image.version="${APT_VERSION}" \
      org.opencontainers.image.vendor="Thermo Fisher Scientific" \
      org.opencontainers.image.licenses="LicenseRef-ThermoFisher-APT-EULA" \
      org.opencontainers.image.description="Proprietary. Redistribution prohibited by the APT EULA; do not publish this image."

COPY --from=fetch /opt/apt/bin/ /opt/apt/bin/
COPY --from=fetch /opt/apt/EULA.docx /opt/apt/EULA.docx
COPY --from=fetch /opt/apt/licenses/ /opt/apt/licenses/

ENV PATH="/opt/apt/bin:${PATH}"

# Smoke test: apt-genotype-axiom writes its version banner to stdout. This
# also records the real version in the build log, which matters because the
# tag on the old image did not match its contents.
RUN apt-genotype-axiom --version
