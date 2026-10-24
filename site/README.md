# Downloads site

Static page that lists the kernel's GitHub releases with download links,
SHA-256 hashes and install notes.

```
site/
├── index.html            markup
├── assets/style.css      theme
├── assets/app.js         fetches releases.json and renders the cards
├── releases.json         fallback index (empty until first deploy)
└── generate_releases.py  builds releases.json from the GitHub API
```

## Local preview

```bash
python3 site/generate_releases.py --out site/releases.json   # needs GH_TOKEN
python3 -m http.server -d site 8080
# http://localhost:8080
```

`generate_releases.py` also accepts `--input saved-api-response.json`, which is
handy for testing the renderer without a token.

## Deployment

`.github/workflows/pages.yml` deploys the folder to GitHub Pages after every
**Build & Release** run whose release changed, on pushes touching `site/`, and
manually through **Actions → Deploy downloads site**.

One-time setup:

1. Repository **Settings → Pages → Build and deployment → Source: GitHub Actions**.
2. Run the workflow once.
3. The site is served from `https://<owner>.github.io/<repo>/`.

> GitHub Pages for a **private** repository needs a plan that includes it
> (Pro/Team/Enterprise). Without Pages the folder still works on any static
> host (Cloudflare Pages, Netlify, nginx) — `releases.json` is the only file
> the deploy step generates.

## Downloads and private releases

Release assets of a private repository require a GitHub login with access, so
the site prefers the **Gofile mirror** that the build records in the release
notes (`- Mirror: https://gofile.io/...`). When no mirror exists the card links
to the GitHub release page and notes that repository access may be required.
