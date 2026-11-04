# Deploy the FeatherOS website to Cloudflare Pages

The static website is in `docs/`, including the standalone downloads page at `/download/`; `wrangler.toml` names the Pages project `featheros` and sets `docs/` as the output directory. Keep the ISO Pages Function in the repository-root `functions/` directory; Cloudflare discovers it automatically during a Pages deployment.

## Deploy to the existing Pages site

1. In the Cloudflare dashboard, open the existing Pages project that serves `https://featheros.pages.dev/`.
2. Connect its Git integration to `RetroByte-Laboratories/FeatherOS` (or update the repository if one is already connected).
3. Set the production branch to `arena/c6d30a0a-featheros`.
4. Select **None** as the framework preset, leave the build command empty, and set the build output directory to `docs`.
5. Save the settings and trigger a production deployment for the selected branch.

Keep using the existing `featheros` project if you need to preserve `https://featheros.pages.dev/`. A different Pages project name receives a different `pages.dev` hostname. Git integration will redeploy after future pushes to the selected production branch.

## ISO download

Cloudflare Pages limits an individual static asset to 25 MiB, so the 3.49 GiB ISO is not copied into the site. Instead, `functions/download/[filename].js` streams the two public GitHub release chunks sequentially as one `application/octet-stream` download at:

`/download/FeatherOS-6.1-eiderdown-desktop-amd64.iso`

The stream supports byte-range requests for resuming downloads and does not buffer the whole ISO in Worker memory. See the [Cloudflare Streams API](https://developers.cloudflare.com/workers/runtime-apis/streams/) and [Workers limits](https://developers.cloudflare.com/workers/platform/limits/). The original part links and SHA256SUMS remain available as a fallback on the Downloads page. If a permanently stored single object is needed instead of a streamed response, use a public Cloudflare R2 bucket.

## Search engines

The site includes a descriptive title, canonical URL, Open Graph metadata, SoftwareApplication structured data, `robots.txt`, and `sitemap.xml`. Google decides when and how to index a new site. After the first deployment, verify the site in Google Search Console and submit `https://featheros.pages.dev/sitemap.xml` to request discovery.
