# Setting up donations

The website's Support section never shows a donate button, link or total that isn't real.

## 1. Create an account with a provider
Pick one that suits you (all have free tiers; fees vary):
- **GitHub Sponsors** — <https://github.com/sponsors> (requires approval; integrates with the repo).
- **Ko-fi** — <https://ko-fi.com>
- **Buy Me a Coffee** — <https://buymeacoffee.com>

## 2. Configure the website
Edit `website/src/config/site.ts`:
```ts
donation: {
  provider: "Ko-fi",                       // shown as “Donate with Ko-fi”
  url: "https://ko-fi.com/your-page",       // must be https://
  goalUSD: 99,
  raisedUSD: null,                          // leave null until you have a verified figure
  raisedAsOf: "",
},
```
- With `url` empty, production builds show “Donations will open soon” and **no button**; development builds show a
  clearly marked setup notice.
- Only set `raisedUSD` from the provider's own dashboard, and set `raisedAsOf` to the date you checked. Update it manually
  (no third-party script or API is used, keeping the site free of trackers).

## 3. Optional
- Add `.github/FUNDING.yml` so GitHub shows a Sponsor button, e.g. `ko_fi: your-page` or `github: [your-username]`.
- Keep the wording honest: donations are voluntary, don't buy a subscription, license or guaranteed feature.
