// @ts-check
import { defineConfig } from "astro/config";
import tailwindcss from "@tailwindcss/vite";
import sitemap from "@astrojs/sitemap";

// SITE_URL: the public origin, e.g. https://owner.github.io (used for canonical and Open Graph URLs).
// BASE_PATH: the sub-path when hosted as a GitHub Pages project site, e.g. /QuickDock.
const site = process.env.SITE_URL || undefined;
const base = process.env.BASE_PATH || "/";

export default defineConfig({
  site,
  base,
  trailingSlash: "ignore",
  integrations: site ? [sitemap()] : [],
  vite: { plugins: [tailwindcss()] },
});
