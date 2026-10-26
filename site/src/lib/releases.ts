const REPO = "playarchway/archway";

export const RELEASES_URL = `https://github.com/${REPO}/releases`;

// GitHub's latest endpoint skips prereleases, so the runtime releases never show up here.
const LATEST_API_URL = `https://api.github.com/repos/${REPO}/releases/latest`;
const CACHE_KEY = "archway-latest-release";

interface ReleaseAsset {
  name: string;
  browser_download_url: string;
}

interface Release {
  tag_name: string;
  assets: ReleaseAsset[];
}

export interface Download {
  version: string;
  url: string;
}

async function fetchLatestRelease(): Promise<Release> {
  const cached = sessionStorage.getItem(CACHE_KEY);
  if (cached) return JSON.parse(cached);

  const response = await fetch(LATEST_API_URL);
  if (!response.ok) throw new Error(`GitHub answered ${response.status}`);
  const release: Release = await response.json();
  sessionStorage.setItem(CACHE_KEY, JSON.stringify(release));
  return release;
}

/** The app archive of the latest release, as uploaded by the release workflow. */
export async function latestDownload(): Promise<Download | null> {
  const release = await fetchLatestRelease();
  const asset = release.assets.find((a) => /^Archway-.+\.zip$/.test(a.name));
  if (!asset) return null;
  return { version: release.tag_name.replace(/^v/, ""), url: asset.browser_download_url };
}
