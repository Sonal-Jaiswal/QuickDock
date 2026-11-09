# Deploying the website

The website in `website/` is a static Astro + Tailwind site. Hosting cost: **$0** on GitHub Pages or Cloudflare Pages.

## Configuration
| What | Where |
| --- | --- |
| Repository owner/name, contact e-mail, donation provider/URL/total | `website/src/config/site.ts` |
| Version, date, DMG name, size, SHA-256, release notes | `website/src/config/release.json` — regenerate with `scripts/update-website-release.sh` |
| Public origin and sub-path | `SITE_URL`, `BASE_PATH` environment variables at build time |
| Screenshots | `website/public/screenshots/` (real captures; see QA report for how they were made) |

Until `repository.owner` is set, the Download button renders as “release not published yet” (no link).

## Local development
```sh
cd website
npm install
npm run dev        # http://localhost:4321
npm run build      # type-checks (astro check) and builds to website/dist
npm run preview
```

## GitHub Pages (recommended)
1. Push the repository to GitHub.
2. Settings › Pages › Build and deployment › Source: **GitHub Actions**.
3. Push to `main`. `.github/workflows/pages.yml` builds and deploys. It derives `SITE_URL`/`BASE_PATH`
   automatically (e.g. `https://owner.github.io` + `/QuickDock`).
4. Custom domain: add it in Settings › Pages, then set repository **variables** `SITE_URL=https://your.domain` and
   `BASE_PATH=/`.

## Cloudflare Pages (alternative)
- Root directory: `website` · Build command: `npm run build` · Output: `dist`
- Environment variables: `SITE_URL=https://<project>.pages.dev`, `BASE_PATH=/`, `NODE_VERSION=22`.

## After each app release
```sh
scripts/build-app.sh && scripts/make-dmg.sh   # or use the DMG published by the Release workflow
scripts/update-website-release.sh
git commit -am "Website: QuickDock <version>" && git push
```
If the release DMG was built in CI, download it and its `.sha256` into `dist/` first so the size and checksum match
the published file exactly.
