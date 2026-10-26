import { fileURLToPath } from "node:url";
import { defineConfig } from "astro/config";

export default defineConfig({
  // The artwork lives with the app in Sources/Archway/Resources.
  vite: { server: { fs: { allow: [fileURLToPath(new URL("..", import.meta.url))] } } },
});
