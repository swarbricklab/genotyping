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
# Thermo Fisher publishes only the current release. At the time of writing
# that is 2.12.0, so it is the default here. The manuscript run used APT
# 2.10.0 (see the README), which Thermo Fisher no longer distributes and
# which therefore cannot be rebuilt from this file. Pass --build-arg to pin a
# different version if you have a URL for it.
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
# 205 MB archive do not end up as layers in the final image.
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim AS fetch

ARG APT_VERSION
ARG APT_URL=https://downloads.thermofisher.com/APT/APT_${APT_VERSION}/apt_${APT_VERSION}_linux_64_x86_binaries.zip
# sha256 of apt_2.12.0_linux_64_x86_binaries.zip (205,220,602 bytes), verified
# against the published download. Override together with APT_VERSION.
ARG APT_SHA256=d715adbc0a14df71e42f14bf250d3c39718d7a6712e8b8b2127192715196bafe

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip \
 && rm -rf /var/lib/apt/lists/*

# Fail the build rather than bake in an unverified archive.
RUN curl -fsSL -o /tmp/apt.zip "${APT_URL}" \
 && printf '%s  /tmp/apt.zip\n' "${APT_SHA256}" | sha256sum -c - \
 && mkdir -p /opt/apt \
 && unzip -q /tmp/apt.zip -d /opt/apt \
 && rm /tmp/apt.zip \
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
