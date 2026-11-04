# Deploy the FeatherOS website to Cloudflare Pages

The static website is in `docs/`; `wrangler.toml` names the Pages project `featheros` and sets `docs/` as the output directory.

## Connect the repository

1. In the Cloudflare dashboard, open **Workers & Pages → Create application → Pages → Connect to Git**.
2. Connect the GitHub repository `RetroByte-Laboratories/FeatherOS`.
3. Choose production branch `arena/c6d30a0a-featheros`.
4. Select **None** as the framework preset, leave the build command empty, and set the build output directory to `docs`.
5. Name the Pages project `featheros`, then deploy. If Cloudflare reports that the project name is already taken, choose an available name; the `pages.dev` URL will use that name.

Once deployed with the requested project name, the public website URL will be `https://featheros.pages.dev/`. Git integration will redeploy it after pushes to the selected production branch.

## ISO download hosting

Cloudflare Pages limits an individual static asset to 25 MiB, so the 3.49 GiB ISO cannot be stored in the Pages site itself. The Downloads page links to the two verified ISO chunks and checksum file on the public GitHub release. To serve one complete ISO from a single URL, it must be stored in object storage such as a public Cloudflare R2 bucket; a bucket and its access settings must be configured in a Cloudflare account before the site can link to it.

## Search engines

The site includes a descriptive title, canonical URL, Open Graph metadata, SoftwareApplication structured data, `robots.txt`, and `sitemap.xml`. Google decides when and how to index a new site. After the first deployment, verify the site in Google Search Console and submit `https://featheros.pages.dev/sitemap.xml` to request discovery.
