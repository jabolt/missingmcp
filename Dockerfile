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
ARG GARMIN_MCP_REF=ea7fe4daabd9d86badc20bae6d6a64412b824302
ENV GARMIN_MCP_REF=${GARMIN_MCP_REF}

# git: uv installs the pinned garmin_mcp worker from a git ref.
# tini: reaps the many worker subprocesses the gateway spawns.
RUN apt-get update && apt-get install -y --no-install-recommends git tini && rm -rf /var/lib/apt/lists/*

COPY pyproject.toml README.md LICENSE ./
COPY src ./src
COPY scripts ./scripts
# mcp<2: garmin_mcp is written against the mcp 1.x API (mcp.server.fastmcp) and
# doesn't bound its own dependency — mcp 2.0.0 (2026-07-28) removed that module,
# and the first image rebuild after the release crashed every worker spawn with
# ModuleNotFoundError (2026-07-31 incident). The worker's other deps float too;
# pin here, in the same resolve, whenever one of them breaks the same way.
RUN uv pip install --system . && \
    uv pip install --system "garmin-mcp @ git+https://github.com/jabolt/garmin_mcp@${GARMIN_MCP_REF}" "mcp<2"
ENTRYPOINT ["tini", "--"]
CMD ["missingmcp"]
EXPOSE 8080
# No VOLUME directive: Railway's builder rejects it ("use Railway Volumes") and
# provides /data via a platform-managed volume; self-hosters mount /data with
# `docker run -v`. Persistence is supplied by the runtime, not the image.
