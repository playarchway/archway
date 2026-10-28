export type Lang = "en" | "de";

/** Each page in both languages; the German pages live under /de. */
export const paths = {
  home: { en: "/", de: "/de/" },
} as const;

export type Page = keyof typeof paths;

export const GITHUB_URL = "https://github.com/playarchway/archway";

const strings = {
  en: {
    source: "Source on GitHub",
    switchLanguage: "Deutsch",
    footer:
      "Archway is early: not every game runs yet, and games with kernel anti-cheat don’t. Licensed under GPL-3.0. Not affiliated with Apple, Valve or CodeWeavers.",
  },
  de: {
    source: "Quellcode auf GitHub",
    switchLanguage: "English",
    footer:
      "Archway steht am Anfang: Noch läuft nicht jedes Spiel, und Spiele mit Kernel-Anti-Cheat laufen nicht. Lizenziert unter GPL-3.0. Nicht verbunden mit Apple, Valve oder CodeWeavers.",
  },
} as const;

export const t = (lang: Lang) => strings[lang];
export const other = (lang: Lang): Lang => (lang === "en" ? "de" : "en");
