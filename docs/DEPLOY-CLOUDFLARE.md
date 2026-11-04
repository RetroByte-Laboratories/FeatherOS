# Deploy the FeatherOS website to Cloudflare Pages

The FeatherOS 6.1 Eiderdown website is in `docs/`. `wrangler.toml` names the Cloudflare Pages project `featheros` and uses `docs/` as the output directory.

## Cloudflare Pages settings

Use the existing Pages project that serves `https://featheros.pages.dev/`:

- GitHub repository: `RetroByte-Laboratories/FeatherOS`
- Production branch: `arena/c6d30a0a-featheros`
- Framework preset: **None**
- Build command: leave blank
- Build output directory: `docs`

Save the settings and trigger a production deployment. The download button is intentionally inactive until the public ISO URL is supplied; when available, add that URL to the button in `docs/index.html`.

## Search engines

The site includes canonical URLs, metadata, SoftwareApplication structured data, `robots.txt`, and `sitemap.xml`. Google decides when and how to index a site. After deployment, verify it in Google Search Console and submit `https://featheros.pages.dev/sitemap.xml` to request discovery.
