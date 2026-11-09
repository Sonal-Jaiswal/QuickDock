/**
 * QuickDock website configuration — the one file to edit for links, contact and donations.
 *
 * Release details (version, file size, checksum, notes) live in `release.json`, which
 * `scripts/update-website-release.sh` regenerates from the built DMG and CHANGELOG.
 *
 * RULES: never put placeholder or unverified URLs, totals or e-mail addresses here.
 * Anything left empty is hidden (or shown as "not available yet") on the live site.
 */
import release from "./release.json";

export const site = {
  name: "QuickDock",
  tagline: "Your Mac, one click away.",
  description:
    "QuickDock is a free, lightweight launcher for macOS. Keep your favourite apps, files, folders, websites and actions one shortcut away — private, offline and beautifully native.",

  /** GitHub repository that hosts the source and the Releases. Leave `owner` empty until it exists. */
  repository: {
    owner: "",
    name: "QuickDock",
  },

  /** Public contact address shown in the footer. Optional. */
  contactEmail: "",

  /** Voluntary donations. See docs/DONATIONS.md. */
  donation: {
    /** Display name of the provider, e.g. "GitHub Sponsors", "Ko-fi", "Buy Me a Coffee". */
    provider: "",
    /** The real donation page URL (https). Empty = no donate button is published. */
    url: "",
    /** First-year goal: Apple Developer Program membership. */
    goalUSD: 99,
    /**
     * Total raised — set ONLY from the provider's own dashboard/records, with the date checked.
     * `null` hides the total entirely.
     */
    raisedUSD: null as number | null,
    raisedAsOf: "", // e.g. "2026-12-01"
  },

  release,
} as const;

// ---------------------------------------------------------------------------
// Derived links. Every helper returns `null` when the underlying value isn't configured,
// so pages can render an honest "not available yet" state instead of a fake link.

const https = (value: string) => (value.startsWith("https://") ? value : null);

export function repoUrl(): string | null {
  const { owner, name } = site.repository;
  return owner && name ? `https://github.com/${owner}/${name}` : null;
}

export function releasesUrl(): string | null {
  const repo = repoUrl();
  return repo ? `${repo}/releases` : null;
}

/** Direct link to this version's DMG on GitHub Releases. */
export function downloadUrl(): string | null {
  const repo = repoUrl();
  return repo ? `${repo}/releases/download/v${site.release.version}/${site.release.fileName}` : null;
}

export function checksumUrl(): string | null {
  const download = downloadUrl();
  return download ? `${download}.sha256` : null;
}

export function issuesUrl(): string | null {
  const repo = repoUrl();
  return repo ? `${repo}/issues` : null;
}

export function readmeUrl(): string | null {
  const repo = repoUrl();
  return repo ? `${repo}#readme` : null;
}

export function donationUrl(): string | null {
  return https(site.donation.url);
}

export function contactEmail(): string | null {
  const email = site.contactEmail.trim();
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email : null;
}

export function formatBytes(bytes: number): string | null {
  if (!bytes) return null;
  const mb = bytes / (1024 * 1024);
  return mb >= 1 ? `${mb.toFixed(1)} MB` : `${Math.round(bytes / 1024)} KB`;
}

/** Prefixes a path with the configured base (needed for GitHub Pages project sites). */
export function asset(path: string): string {
  const base = import.meta.env.BASE_URL.endsWith("/") ? import.meta.env.BASE_URL : `${import.meta.env.BASE_URL}/`;
  return base + path.replace(/^\//, "");
}
