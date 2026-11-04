# Deploy RetroByte Laboratories to Cloudflare Pages

The `docs/` directory is the complete site for `https://retrobyte-laboratories.pages.dev/`. It contains the RetroByte Laboratories homepage, the FeatherOS project at `/featheros/`, and the FeatherOS downloads page at `/featheros/download/`. `wrangler.toml` sets the Pages project name to `retrobyte-laboratories` and the output directory to `docs/`.

## Cloudflare Pages settings

In the Cloudflare dashboard, create a Pages project named `retrobyte-laboratories` (or select it if it already exists), then connect this repository:

- GitHub repository: `RetroByte-Laboratories/FeatherOS`
- Production branch: `arena/c6d30a0a-featheros`
- Framework preset: **None**
- Build command: leave blank
- Build output directory: `docs`
- Site URL: `https://retrobyte-laboratories.pages.dev/`

Keep the Pages Function in the repository-root `functions/` directory. Cloudflare discovers `functions/featheros/download/[filename].js` during a Pages deployment. The legacy `featheros.pages.dev` project is separate; do not use it as the deployment target for this combined site. Retire that old project only after the new site and FeatherOS page are verified.

## FeatherOS ISO delivery

The current public GitHub release is [`v6.1-eiderdown-rebuild-5260d4c`](https://github.com/RetroByte-Laboratories/FeatherOS/releases/tag/v6.1-eiderdown-rebuild-5260d4c). It stores the 3.49 GiB ISO in two release assets because the full image is larger than GitHub's per-asset limit.

The FeatherOS download page links to the two parts and `SHA256SUMS` as fallbacks. Its **Download the full ISO** button is an explicit user click; it requests `/featheros/download/FeatherOS-6.1-eiderdown-desktop-amd64.iso`. The Pages Function streams the two GitHub assets sequentially as a single ISO response and supports byte-range requests. It does not buffer or store a second merged copy of the ISO.

## Search engines

The site includes canonical URLs, metadata, SoftwareApplication/Organization structured data, `robots.txt`, and `sitemap.xml`. Google decides when and how to index a new site; after deployment, verify the property in Google Search Console and submit `https://retrobyte-laboratories.pages.dev/sitemap.xml` to request discovery.
