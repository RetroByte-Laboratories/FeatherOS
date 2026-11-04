# Deploy the FeatherOS website to Cloudflare Pages

The static website is in `docs/`; `wrangler.toml` names the Pages project `featheros` and sets `docs/` as the output directory.

## Connect the repository

1. In the Cloudflare dashboard, open **Workers & Pages → Create application → Pages → Connect to Git**.
2. Connect the GitHub repository `RetroByte-Laboratories/FeatherOS`.
3. Choose production branch `arena/c6d30a0a-featheros`.
4. Select **None** as the framework preset, leave the build command empty, and set the build output directory to `docs`.
5. Name the Pages project `featheros`, then deploy. If Cloudflare reports that the project name is already taken, choose an available name; the `pages.dev` URL will use that name.

Once deployed with the requested project name, the public website URL will be `https://featheros.pages.dev/`. Git integration will redeploy it after pushes to the selected production branch.

## ISO download

Cloudflare Pages limits an individual static asset to 25 MiB, so the 3.49 GiB ISO is not copied into the site. Instead, `functions/download/[filename].js` streams the two public GitHub release chunks sequentially as one `application/octet-stream` download at:

`/download/FeatherOS-6.1-eiderdown-desktop-amd64.iso`

The stream supports byte-range requests for resuming downloads and does not buffer the whole ISO in Worker memory. See the [Cloudflare Streams API](https://developers.cloudflare.com/workers/runtime-apis/streams/) and [Workers limits](https://developers.cloudflare.com/workers/platform/limits/). The original part links and SHA256SUMS remain available as a fallback on the Downloads page. If a permanently stored single object is needed instead of a streamed response, use a public Cloudflare R2 bucket.

## Search engines

The site includes a descriptive title, canonical URL, Open Graph metadata, SoftwareApplication structured data, `robots.txt`, and `sitemap.xml`. Google decides when and how to index a new site. After the first deployment, verify the site in Google Search Console and submit `https://featheros.pages.dev/sitemap.xml` to request discovery.
