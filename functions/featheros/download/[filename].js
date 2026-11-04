const ISO_NAME = "FeatherOS-6.1-eiderdown-desktop-amd64.iso";
const PARTS = [
  {
    url: "https://github.com/RetroByte-Laboratories/FeatherOS/releases/download/v6.1-eiderdown-rebuild-5260d4c/FeatherOS-6.1-eiderdown-desktop-amd64.iso.part-00",
    size: 1992294400,
  },
  {
    url: "https://github.com/RetroByte-Laboratories/FeatherOS/releases/download/v6.1-eiderdown-rebuild-5260d4c/FeatherOS-6.1-eiderdown-desktop-amd64.iso.part-01",
    size: 1758470144,
  },
];
const ISO_SIZE = PARTS.reduce((sum, part) => sum + part.size, 0);

function parseRange(value) {
  if (!value) return null;
  if (value.includes(",")) return undefined; // Multiple ranges are not supported.

  const match = /^bytes=(\d*)-(\d*)$/i.exec(value.trim());
  if (!match || (!match[1] && !match[2])) return undefined;

  if (!match[1]) {
    const suffixLength = Number(match[2]);
    if (!Number.isSafeInteger(suffixLength) || suffixLength <= 0) return undefined;
    return {
      start: Math.max(0, ISO_SIZE - suffixLength),
      end: ISO_SIZE - 1,
    };
  }

  const start = Number(match[1]);
  const requestedEnd = match[2] ? Number(match[2]) : ISO_SIZE - 1;
  if (!Number.isSafeInteger(start) || !Number.isSafeInteger(requestedEnd)) return undefined;
  if (start >= ISO_SIZE || requestedEnd < start) return undefined;
  return { start, end: Math.min(requestedEnd, ISO_SIZE - 1) };
}

function getSegments(start, end) {
  const segments = [];
  let offset = 0;
  for (const part of PARTS) {
    const partEnd = offset + part.size - 1;
    const overlapStart = Math.max(start, offset);
    const overlapEnd = Math.min(end, partEnd);
    if (overlapStart <= overlapEnd) {
      segments.push({
        url: part.url,
        localStart: overlapStart - offset,
        localEnd: overlapEnd - offset,
      });
    }
    offset += part.size;
  }
  return segments;
}

export async function onRequest({ request, params }) {
  if (params.filename !== ISO_NAME) {
    return new Response("Not found", { status: 404 });
  }
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Method not allowed", {
      status: 405,
      headers: { Allow: "GET, HEAD" },
    });
  }

  const rangeHeader = request.headers.get("Range");
  const range = parseRange(rangeHeader);
  if (rangeHeader && !range) {
    return new Response(null, {
      status: 416,
      headers: {
        "Accept-Ranges": "bytes",
        "Content-Range": `bytes */${ISO_SIZE}`,
      },
    });
  }

  const start = range ? range.start : 0;
  const end = range ? range.end : ISO_SIZE - 1;
  const headers = new Headers({
    "Accept-Ranges": "bytes",
    "Cache-Control": "no-store",
    "Content-Disposition": `attachment; filename="${ISO_NAME}"`,
    "Content-Length": String(end - start + 1),
    "Content-Type": "application/octet-stream",
    "X-Content-Type-Options": "nosniff",
  });
  if (range) headers.set("Content-Range", `bytes ${start}-${end}/${ISO_SIZE}`);

  const status = range ? 206 : 200;
  if (request.method === "HEAD") return new Response(null, { status, headers });

  const { readable, writable } = new TransformStream();
  const segments = getSegments(start, end);
  const pump = (async () => {
    try {
      for (const segment of segments) {
        const upstreamHeaders = range
          ? { Range: `bytes=${segment.localStart}-${segment.localEnd}` }
          : undefined;
        const upstream = await fetch(segment.url, {
          headers: upstreamHeaders,
          redirect: "follow",
        });
        if (!upstream.ok || !upstream.body) {
          throw new Error(`Release asset fetch failed with status ${upstream.status}`);
        }
        if (range && upstream.status !== 206) {
          throw new Error("Release asset origin did not honor the requested byte range");
        }
        await upstream.body.pipeTo(writable, { preventClose: true });
      }
      await writable.close();
    } catch (error) {
      console.error("FeatherOS ISO stream failed", error);
      try {
        await writable.abort(error);
      } catch {
        // The client may already have cancelled the download.
      }
    }
  })();
  void pump;

  return new Response(readable, { status, headers });
}
