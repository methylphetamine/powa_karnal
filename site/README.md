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
GITHUB_REPOSITORY=methylphetamine/powa_karnal python3 site/generate_releases.py
python3 -m http.server -d site 8080
# http://localhost:8080
```

`generate_releases.py` also accepts `--input saved-api-response.json`, which is
handy for testing the renderer without hitting the API. `GH_TOKEN` is optional
for this public repository and only raises the API rate limit.

## Deployment

`.github/workflows/pages.yml` deploys the folder to GitHub Pages after every
**Build & Release** run, on pushes touching `site/`, and manually through
**Actions → Deploy downloads site**.

The site is served from `https://methylphetamine.github.io/powa_karnal/`
(repository **Settings → Pages → Source: GitHub Actions**).

## Downloads

Release assets are public. Each card has a **Direct download** button for the
ZIP on GitHub Releases and, when the release notes contain a Gofile link, a
**Gofile mirror** button next to it.
