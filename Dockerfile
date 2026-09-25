FROM python:3.12-slim
RUN pip install --no-cache-dir uv
WORKDIR /app

# Pin the unmodified garmin_mcp worker to a reviewed commit (override at build
# time). Bumping this is a deliberate, reviewed action: the worker runs with each
# user's decrypted Garmin tokens, so a floating ref would run unreviewed code.
# e8554bc (2026-09-01): reviewed 2026-09-03 — no dependency additions, no new
# network destinations; NOTE the worker now logs in on a background thread and
# answers /healthz before the sign-in resolves, which is why WorkerManager gates
# spawns on the sign-in log lines (forward.login_outcome).
# cb320b5 (2026-09-20, jabolt/garmin_mcp): reviewed 2026-09-20 — upstream 655efb8
# (12 commits since e8554bc: no dependency changes, stdlib-only new imports, no
# new network destinations, sign-in log lines unchanged) plus the fork's
# configurable food region (GARMIN_FOOD_REGION, default GB).
# 33f26f5 (2026-09-20, jabolt/garmin_mcp): reviewed 2026-09-20 — fork-only change on top
# of cb320b5: search_foods sends regionCode/languageCode (as Garmin Connect web does),
# with a 400-only fallback; no upstream commits, no dependency changes.
# ea7fe4d (2026-09-21, jabolt/garmin_mcp): reviewed 2026-09-21 — fork-only change on top
# of 33f26f5: optional stateless streamable-http (GARMIN_MCP_STATELESS, off by default),
# so a recycled worker cannot strand clients on a dead MCP session; no dependency changes.
# 5f903c4 (2026-09-21, jabolt/garmin_mcp): reviewed 2026-09-21 — fork-only change on top
# of ea7fe4d: six Lifestyle Logging write tools in a new module (same connectapi host as
# the existing read tool); no dependency changes, no new network destinations.
# b44a0a0 (2026-09-25, jabolt/garmin_mcp): reviewed 2026-09-25 — fork-only change on top
# of 5f903c4: course tools tolerate Garmin's null coursePoints; download_course_gpx returns
# Garmin's own GPX export inline (same connectapi host); no dependency changes.
# cb8e597 (2026-09-25, jabolt/garmin_mcp): reviewed 2026-09-25 — fork-only change on top
# of b44a0a0: download_course_gpx returns a summary (start/finish) unless include_gpx;
# no dependency changes, no new network destinations.
# d409705 (2026-09-25, jabolt/garmin_mcp): reviewed 2026-09-25 — fork-only change on top
# of cb8e597: read-only get_course_location_share (course start/finish for an Apple Maps
# share to the watch); no dependency changes, no new network destinations.
# bdae41d (2026-09-25, jabolt/garmin_mcp): reviewed 2026-09-25 — fork-only change on top
# of d409705: course tools steer watch saved locations to get_course_location_share
# (description and response text only); no dependency changes.
# 778a255 (2026-09-25, jabolt/garmin_mcp): reviewed 2026-09-25 — fork-only change on top
# of bdae41d: port to mcp 2.x MCPServer so the worker answers MCP 2026-07-28
# (server/discover, tools/list ttlMs) as well as initialize-handshake clients. New deps
# via mcp 2.2: mcp-types, opentelemetry-api (API only, no exporter), httpx2, truststore;
# no new network destinations. Needs the proxy to forward MCP-Protocol-Version /
# Mcp-Method / Mcp-Name / Mcp-Param-* (this commit).
ARG GARMIN_MCP_REF=778a25547b028d65c45baedc16ff0b7773d78183
ENV GARMIN_MCP_REF=${GARMIN_MCP_REF}

# git: uv installs the pinned garmin_mcp worker from a git ref.
# tini: reaps the many worker subprocesses the gateway spawns.
RUN apt-get update && apt-get install -y --no-install-recommends git tini && rm -rf /var/lib/apt/lists/*

COPY pyproject.toml README.md LICENSE ./
COPY src ./src
COPY scripts ./scripts
# mcp>=2.2,<3: the pinned worker uses the mcp 2.x MCPServer API (ported 2026-09-25;
# before that it needed mcp<2, see the 2026-07-31 incident when mcp 2.0.0 removed
# mcp.server.fastmcp). The worker bounds mcp itself now; pinning it here too keeps a
# future major release from reaching an image rebuild. The worker's other deps float;
# pin here, in the same resolve, whenever one of them breaks the same way.
RUN uv pip install --system . && \
    uv pip install --system "garmin-mcp @ git+https://github.com/jabolt/garmin_mcp@${GARMIN_MCP_REF}" "mcp>=2.2.0,<3"
ENTRYPOINT ["tini", "--"]
CMD ["missingmcp"]
EXPOSE 8080
# No VOLUME directive: Railway's builder rejects it ("use Railway Volumes") and
# provides /data via a platform-managed volume; self-hosters mount /data with
# `docker run -v`. Persistence is supplied by the runtime, not the image.
