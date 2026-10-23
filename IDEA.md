# IDEA — Open-Source Windows Gaming Launcher für macOS

> **Status:** Technischer Machbarkeitsnachweis in Umsetzung
> **Arbeitstitel:** Overcross
> **Plattform:** macOS auf Apple Silicon (M-Serie)  
> **Fokus:** Windows-Indie-Games möglichst unkompliziert auf dem Mac spielen

## 1. Kurzbeschreibung

Eine kostenlose, quelloffene macOS-App, mit der Nutzer Windows-Spiele ohne eigene Windows-Installation starten können. Die App kombiniert bestehende Kompatibilitätstechnologien wie **Wine**, **Rosetta 2** und unterschiedliche Grafik-Backends mit einer modernen, nativen Benutzeroberfläche.

**Produktversprechen:** Bei getesteten Spielen richtet die App eine bekannte Konfiguration möglichst automatisch ein. Unbekannte Spiele können experimentell importiert und mit manueller Hilfe ausprobiert werden; dafür gibt es keine Kompatibilitätsgarantie.

Die App entwickelt **keine eigene vollständige Windows-Kompatibilitätsschicht**. Ihr Mehrwert liegt in der Orchestrierung bestehender Technologien, der automatischen Konfiguration und einer angenehmen Spielerfahrung.

## 2. Problem und Zielgruppe

### Problem

- Viele Indie-Games erscheinen nur für Windows, obwohl ihre Hardwareanforderungen auf aktuellen Macs problemlos erfüllbar wären.
- Wine-Konfigurationen, Grafik-Backends und Windows-Abhängigkeiten sind für Gelegenheitsspieler unübersichtlich.
- CrossOver ist kostenpflichtig; alternative Tools bieten unterschiedliche Kompatibilität und Benutzerfreundlichkeit.
- Ein Spiel, das grundsätzlich funktioniert, kann aufgrund falscher Bottle-, DLL- oder Grafikeinstellungen trotzdem scheitern.

### Zielgruppe

- Nutzer von Apple-Silicon-Macs, die Windows-Indie-Spiele spielen möchten.
- Spieler mit Windows-Spielen aus Steam, itch.io, GOG oder lokalen Installationsdateien.
- Technisch interessierte Nutzer, die eine freie und transparente Lösung bevorzugen.

## 3. Vision und Abgrenzung

**Vision:** Eine macOS-Gaming-Bibliothek, die für bekannte Spiele getestete Laufzeiten und Konfigurationen bereitstellt und bei unbekannten Spielen nachvollziehbare Experimente ermöglicht.

**Kein Ziel für die erste Version:**

- Alle Windows-AAA-Spiele zuverlässig auszuführen.
- Wine oder D3DMetal von Grund auf neu zu implementieren.
- Windows-Kernel-Treiber, Kernel-Anti-Cheat oder beliebige DRM-Systeme zu unterstützen.
- Ein eigener Steam-, Epic- oder GOG-Store, ein Checkout oder ein Ersatz für diese Clients zu sein. Der Steam-Katalog gekaufter Spiele gehört zum MVP.
- Native macOS-Spiele aus Steam zu starten; nicht unterstützte oder native Titel können im Steam-Katalog erscheinen, ohne dass der MVP sie starten kann.
- Online-Koop im MVP zu unterstützen.
- Windows-Spiele in native macOS-Apps zu konvertieren.

## 4. Technische Grundlagen

| Technologie | Rolle |
| --- | --- |
| **Wine** | Implementierung von Windows-APIs und Ausführung von Windows-Anwendungen ohne Windows-Installation |
| **Rosetta 2** | Ausführung kompatiblen x86-64-Codes auf Apple Silicon; Einschränkungen bleiben bestehen |
| **D3DMetal** (aus Apples Game Porting Toolkit) | Übersetzung unterstützter Direct3D-11/12-Grafikpfade nach Metal; proprietär und lizenzrechtlich gesondert zu behandeln |
| **DXMT** | Alternative Direct3D-11-zu-Metal-Implementierung |
| **DXVK** | Direct3D-9/10/11-Übersetzung nach Vulkan; auf macOS zusätzlich eine geeignete Vulkan-zu-Metal-Schicht nötig |
| **WineD3D** | Weitere, je nach Spiel geeignete Grafikoption |
| **Metal** | Native Grafik-API von Apple |

**Wichtig:** Das Game Porting Toolkit ist kein fertiges Framework, das sämtliche Windows-Spiele selbstständig startet. CrossOver und andere Projekte kombinieren unterschiedliche Laufzeit- und Grafikkomponenten. Die genaue Kompatibilität hängt vom Spiel, der Architektur, den verwendeten APIs und der jeweiligen Version ab.

## 5. Vorgeschlagene Architektur

**Versionsstrategie:** Ziel sind aktuelle Wine- und Steam-Versionen. Eine ältere Wine-Version ist keine akzeptierte Lösung für Kompatibilitätsprobleme. Verfügbare macOS-Pakete und neueste Upstream-Versionen werden ausdrücklich unterschieden.

```text
Mac Gaming Launcher
├── User Interface
│   ├── Game Library
│   ├── Game Details & Settings
│   └── Import / Installation Flow
├── Game Manager
│   ├── Game Metadata
│   ├── Installations & Shortcuts
│   └── Compatibility Profiles
├── Bottle Manager
│   ├── Create / Remove / Clone
│   ├── Windows Version & Environment
│   └── DLLs & Dependencies
├── Runtime Manager
│   ├── Wine Runtime Selection
│   ├── Runtime Installation / Updates
│   └── Rosetta Prerequisites
├── Graphics Backend Manager
│   ├── DXMT
│   ├── DXVK (+ Vulkan/Metal Layer)
│   ├── WineD3D
│   └── D3DMetal (optional, license-dependent)
├── Game Launcher
│   ├── Process Execution
│   ├── Environment & DLL Overrides
│   └── Logs / Crash Diagnostics
└── Persistence
    ├── SQLite
    └── JSON-based Game Profiles
```

### Beispielhafter Startablauf

1. Der Nutzer wählt ein bekanntes Spielprofil oder importiert experimentell eine `.exe` beziehungsweise einen vorhandenen Spieleordner.
2. Die App ermittelt grundlegende Informationen und sucht nach einer getesteten Konfiguration. Für unbekannte Spiele weist sie auf den experimentellen Status hin.
3. Der Bottle Manager legt eine isolierte Wine-Umgebung an.
4. Der Runtime Manager stellt eine ausgewählte, frei nutzbare Laufzeit bereit; die konkrete Runtime-Wahl ist offen.
5. Der Graphics Backend Manager verwendet ein für das Spiel getestetes Backend oder lässt eine manuelle Auswahl zu.
6. Für den ersten PoC dient der Windows-Steam-Client innerhalb der Wine-Umgebung vorläufig zur Anmeldung und Installation des Testspiels. Native macOS-Steam-Installationen werden nicht als Quelle für Windows-Spieldateien vorausgesetzt.
7. Der Nutzer sieht seine Steam-Spiele in der eigenen Bibliotheksoberfläche, unabhängig davon, ob sie installiert oder bereits getestet sind. Nach der Installation startet die App das Spiel über den Windows-Steam-Client in derselben Bottle. Logs und Laufzeitstatus werden gesammelt; erfolgreiche Konfigurationen können lokal gespeichert und später als Profile geteilt werden.

**Hinweis:** Die automatische Erkennung der benötigten Grafik-API ist nicht immer zuverlässig möglich. Nur für konkret getestete Spiele kann eine bekannte Konfiguration als getestet gelten. Unbekannte Importe bleiben Experimente; Installer-Unterstützung ist noch nicht entschieden.

### Steam-Anbindung: vorgeschlagener MVP-Weg

- Die Bibliotheksoberfläche gehört zu unserer App und zeigt im MVP alle über Steam ermittelten gekauften Spiele, auch wenn sie nicht installiert oder für diese App nicht getestet sind. Ein Eintrag im Katalog bedeutet nicht, dass das Spiel unterstützt oder startbar ist.
- `IPlayerService/GetOwnedGames` ist die geplante Quelle für den Steam-Katalog. Die Einrichtung benötigt eine SteamID, einen Web-API-Schlüssel und sichtbare Spieldaten. Der Nutzer richtet den API-Zugang selbst ein; Aufwand für Identität und Datenschutz ist akzeptiert. Zugangsdaten werden lokal sicher gespeichert (zum Beispiel im macOS-Schlüsselbund), nie in die App eingebettet oder mit anderen Nutzern geteilt. Der Schlüssel wird nicht hier oder im Konzept angefordert.
- Der Katalog unterscheidet installierte und nicht installierte Spiele sowie getestet, experimentell und ungetestet; verfügbare Plattformangaben werden angezeigt. Eine leere Bibliothek, private oder nicht sichtbare Spieldaten, Authentifizierungsfehler und Netzwerkfehler werden als unterschiedliche Zustände dargestellt.
- Eine lokale Cache-Kopie hält die Bibliothek reaktionsfähig und bewahrt die zuletzt erfolgreich geladenen Daten bei API- oder Netzwerkfehlern.
- Installation und Spielstart werden an den Windows-Steam-Client innerhalb derselben Bottle übergeben, beispielsweise über `steam://install/5228920` und `steam.exe -applaunch 5228920`. Steam übernimmt Anmeldung, Downloads und Updates. Die konkrete Steuerung unter Wine muss im PoC geprüft werden. Die Kataloganzeige erfolgt in der Oberfläche unserer App; der Steam-Client ist nicht als Bibliotheksoberfläche vorausgesetzt.
- Steam muss nicht dauerhaft seine Hauptoberfläche anzeigen. `-silent` erlaubt einen Start im Hintergrund, kann aber weiterhin einen Login-Dialog öffnen. Für Anmeldung, Steam Guard, Installation oder Fehler dürfen Steam-Fenster erscheinen; ein vollständig oberflächenloser Ablauf wird nicht vorausgesetzt.
- SteamCMD ist vorerst keine MVP-Abhängigkeit. Seine Eignung für den Download dieses konkreten Kaufspiels ist nicht nachgewiesen; ein vollständiger Ersatz des Steam-Clients wird daraus nicht abgeleitet.

Quellen: [Steam Web API: GetOwnedGames](https://partner.steamgames.com/doc/webapi/IPlayerService?l=english), [API-Schlüssel](https://partner.steamgames.com/doc/webapi_overview/auth), [Steam-Startoptionen](https://help.steampowered.com/en/faqs/view/0188-6BB7-D467-08E1), [Valve Developer Community: Kommandozeilenoptionen](https://developer.valvesoftware.com/wiki/Command_Line_Options#Steam), [Valve: Steam-Installationslinks](https://partner.steamgames.com/doc/steamhardware/loadgames).

## 6. Tech-Stack

**Festgelegt:** SwiftUI und Swift für die native macOS-App.

- **SwiftUI** für eine native macOS-Oberfläche.
- **Swift** für Bottle-, Prozess-, Datei- und Runtime-Verwaltung.
- **SQLite** für Spielebibliothek, Installationen, Einstellungen und Profile.
- **JSON** für versionierbare Kompatibilitätsrezepte.
- **Wine und vorhandene Grafik-Backends** als separate, austauschbare Laufzeitkomponenten.

SQLite und JSON bleiben Vorschläge für die Datenhaltung. Runtime und Grafik-Backend werden anhand des technischen Machbarkeitsnachweises gewählt. Die Wahl von SwiftUI und Swift ersetzt keine Messung von Reaktionszeiten und Ressourcenverbrauch.

### UI- und Qualitätsziele

- Die Oberfläche soll hochwertig und durchdacht gestaltet sein. Vor der konkreten UI-Implementierung sollen später mit Claude mehrere Designvarianten erstellt und verglichen werden; das ist ein geplanter Arbeitsschritt, keine Festlegung auf eine Variante.
- Die Bibliothek soll dank lokaler Cache-Daten reaktionsfähig bleiben. Cover werden erst bei Bedarf geladen.
- Die App soll performant und speicherschonend sein. RAM- und Speicherplatzbedarf sind Qualitätsziele, aber noch ohne Zahlen; Budgets werden nach Messungen auf dem Ziel-Mac festgelegt.
- Messungen unterscheiden App-Leerlauf, App-Start und Bibliotheksaktionen von den Ressourcen, die Wine, Windows-Steam und das Spiel benötigen.
- Vor dem technischen Machbarkeitsnachweis muss noch keine polierte Oberfläche fertig sein.

## 7. MVP: Erste spielbare Version

### Muss-Funktionen

- [ ] Apple-Silicon-macOS-App mit eigener, reaktionsfähiger Bibliotheksoberfläche für alle über `GetOwnedGames` ermittelten gekauften Steam-Spiele, einschließlich nicht installierter Spiele.
- [ ] SteamID und Web-API-Schlüssel lokal einrichten und sicher speichern; leere Bibliothek, private Spieldaten, Authentifizierungs- und Netzwerkfehler unterscheidbar anzeigen und zuletzt geladene Daten aus dem lokalen Cache verfügbar halten.
- [ ] Installationsstatus, Teststatus (getestet, experimentell, ungetestet) und verfügbare Plattformangaben pro Katalogeintrag anzeigen, ohne daraus Unterstützung abzuleiten.
- [ ] Für den ersten PoC den Windows-Steam-Client innerhalb einer Wine-Umgebung ausführen; vorläufig laufen Anmeldung und Download des ersten Testspiels über diesen Client.
- [ ] Das installierte Spiel aus der eigenen Spielebibliothek über den Windows-Steam-Client in derselben Bottle starten können.
- [ ] Für den ersten Steam-Titel eine eigene, wiederverwendbare Bottle anlegen. Die Isolationsregel für weitere Steam-Spiele bleibt offen.
- [ ] Eine frei nutzbare Wine-Runtime und ein frei nutzbares Grafik-Backend auswählen, mit denen sich Windows-Steam und das Testspiel starten lassen. Auswahl und macOS-Unterstützung müssen noch entschieden und technisch nachgewiesen werden.
- [ ] Lokale Windows-EXE oder vorhandenen Spieleordner experimentell importieren können; Installer-Unterstützung ist noch nicht festgelegt.
- [ ] Spiel starten, stoppen und Beendigungsstatus anzeigen.
- [ ] Logs sichtbar machen und als Datei exportieren.
- [ ] Grafik-Backend und zentrale Bottle-Einstellungen manuell umschaltbar machen.
- [ ] Das erste Zielspiel bis zum tatsächlichen Spielen und Laden eines gespeicherten Spielstands validieren; weitere Spiele kommen nach diesem ersten Nachweis hinzu.

### Erstes Validierungsziel

[Brick by Brick: Tidy Up the Small Town! von PaperPixel Games (Steam-App 5228920)](https://store.steampowered.com/app/5228920/Brick_by_Brick_Tidy_Up_the_Small_Town/) ist das erste Ziel. Die Kompatibilität ist unbestätigt und darf erst nach erfolgreichem Test als unterstützt bezeichnet werden. Der Testumfang beschränkt sich auf Einzelspieler: zunächst Anmeldung und Installation über den Windows-Steam-Client in der Wine-Umgebung, danach Start aus der eigenen Spielebibliothek, tatsächliches Spielen, Speichern, Beenden, erneuter Start und Laden des Spielstands. Dabei wird auch geprüft, welche Steam-Fenster im Ablauf erscheinen. Online-Koop ist nicht Teil dieses Nachweises.

### Festgelegte erste Testplattform

- Der lokale Mac des Nutzers mit **Apple M5 Pro** und **24 GB RAM**.
- **macOS 27.0.1**, lokal ausgelesen und vom Nutzer als erste Testplattform bestätigt.
- Kompatibilitäts- und Ressourcenmessungen beziehen sich zunächst auf diese Konfiguration. Bei Tests werden zusätzlich die genauen Runtime-, Backend-, Steam- und Spielversionen dokumentiert; die Ergebnisse gelten nicht automatisch für andere Macs oder macOS-Versionen.

### Technisches MVP-Erfolgskriterium

Der gewählte, frei nutzbare Runtime- und Backend-Stack kann Windows-Steam innerhalb der Wine-Umgebung für die Anmeldung und Installation des ersten Validierungsziels ausführen. Anschließend kann der Nutzer das Spiel aus unserer Bibliothek starten, spielen und nach einem Neustart einen Spielstand laden. CrossOver ist weder Voraussetzung noch ausgewählte Runtime. Für getestete Spiele kann die App bekannte Konfigurationen automatisch anwenden; unbekannte EXE- und Ordnerimporte bleiben experimentell und ohne Kompatibilitätsversprechen.

Die erste nutzbare Version ist zunächst für den persönlichen Einsatz auf der oben festgelegten Testplattform vorgesehen. Während des Proof of Concept ist manuelles Setup durch den Entwickler zulässig. Die App soll im späteren Nutzer-Workflow weiterhin ohne Terminal auskommen. Breite Geräteunterstützung sowie Signierung und Notarisierung gehören zu einer späteren öffentlichen Veröffentlichung.

## 8. Erweiterungen nach dem MVP

**Phase 2 — Komfort**

- Spielecover, Metadaten und anpassbare Bibliotheksansicht.
- Installation über GOG-/itch.io-Downloads oder Installerdateien.
- Winetricks-ähnliche Installation häufiger Abhängigkeiten, soweit lizenziert und technisch geeignet.
- Mehrere Wine-Versionen und Grafik-Backends verwalten.
- Backups, Exporte und Klonen von Bottles.

**Phase 3 — Intelligente Kompatibilität**

- Community-Datenbank mit getesteten Spieleprofilen.
- Automatisierte Konfigurationsvorschläge für einzelne Spiele.
- Erfassung von anonymisierten, freiwillig geteilten Kompatibilitätsergebnissen.
- Diagnose typischer Startprobleme anhand von Logs.
- Optional KI-gestützte Vorschläge, immer mit nachvollziehbaren Änderungen.

**Phase 4 — Ökosystem**

- Bibliotheksintegrationen für weitere Stores.
- Online-Koop für Steam-Spiele.
- Weitere Stores und Launcher.
- Controller-Profile, Spielstände-Management und Updates.
- Signierte/notarisierte Releases mit nachvollziehbarer Runtime-Verteilung.

## 9. Lizenzierung und Distribution

Dieser Punkt ist **vor einer öffentlichen Veröffentlichung** verbindlich zu prüfen:

- **Wine und weitere Open-Source-Projekte:** jeweilige Lizenztexte, Copyright-Hinweise und Pflichten bei Modifikationen/Weiterverteilung einhalten.
- **Apples D3DMetal/Game Porting Toolkit:** proprietär. Nicht davon ausgehen, dass das Mitliefern der Bibliotheken in einer fremden Open-Source-App erlaubt ist, nur weil CrossOver sie verwendet.
- **Optionale GPTK-Nutzung:** zunächst nur als technische Möglichkeit untersuchen; auch die Verwendung einer lokal installierten GPTK-Kopie muss mit den geltenden Apple-Bedingungen vereinbar sein.
- **Spiele:** keine Weitergabe proprietärer Spiele, Assets oder Store-Zugangsdaten.
- **Distribution:** macOS-Code-Signing, Notarisierung, Berechtigungen und Runtime-Downloads berücksichtigen.

**Pragmatische Strategie:** Zunächst einen vollständig nutzbaren MVP auf Basis zulässig weiterverteilbarer Komponenten bauen. Die Integration proprietärer Apple-Technologie getrennt evaluieren und erst nach Lizenzprüfung anbieten.

## 10. Größte technische Risiken

| Risiko | Umgang damit |
| --- | --- |
| Unterschiedliche Wine-Builds und macOS-Versionen | Versionierte, getestete Runtime-Pakete und reproduzierbare Konfigurationen |
| Allgemeine Rosetta-Unterstützung endet nach macOS 27 | Die erprobte Wine-Runtime ist x86_64 und benötigt Rosetta. macOS 28 wird nicht als unterstützt zugesagt; Runtime austauschbar halten und eine geeignete Übersetzungslösung neu validieren. Eine native SwiftUI-Oberfläche entfernt diese Runtime-Abhängigkeit nicht. |
| Grafikkompatibilität variiert pro Spiel | Austauschbare Backends und spielbezogene Profile |
| Anti-Cheat/DRM oder Steam-Abhängigkeiten verhindern Starts | Einschränkungen pro getestetem Spiel dokumentieren; Kompatibilität nicht pauschal versprechen |
| 32-Bit-Spiele / alte Windows-APIs | Früh gezielt testen und Unterstützung nicht pauschal versprechen |
| Proprietäre GPTK-Komponenten | Nicht voraussetzen, dass Distribution oder allgemeine Nutzung erlaubt ist |
| Wine-Prozess- und Dateisystemdetails | Zuerst mit wenigen Referenzspielen stabilisieren |
| Updates brechen funktionierende Spiele | Versionen pro Bottle fixieren; Rollback ermöglichen |
| Leistungs- und Speicherbedarf ist noch unbekannt | Launcher-Leerlauf, Start und Bibliotheksaktionen getrennt von Wine, Steam und Spiel messen; RAM- und Speicherbudgets danach festlegen |

Apple kündigt Rosetta ab macOS 28 nur noch für bestimmte ältere, nicht mehr gepflegte Spiele mit Intel-Frameworks an. Dass Wine oder Windows-Spiele unter Wine unter diese Ausnahme fallen, ist nicht bestätigt. Der erste Ziel-Mac bleibt deshalb die festgelegte macOS-27.0.1-Konfiguration. Quelle: [Apple: Rosetta auf dem Mac](https://support.apple.com/en-us/102527).

## 11. Grobe Umsetzungsschritte

**Aktueller Stand:** Ein SwiftPM-Paket mit wiederverwendbarem Kern und CLI für Diagnose, Runtime-Konfiguration, eigene Wine-Bottle sowie Steam-Installations- und Startanforderungen ist implementiert. Neun automatisierte Tests bestehen. Wine 11.18 und die Bottle-Einrichtung wurden auf dem Ziel-Mac tatsächlich ausgeführt. Windows-Steam ist installiert und aktualisiert, zeigt unter Wine 11.18 aber ein schwarzes Fenster. Die Diagnose läuft; Anmeldung und Spieltest sind noch nicht bestätigt. SwiftUI-Oberfläche und Steam-Katalogabfrage folgen nach dem ersten Spielnachweis. Details: [Runtime-Protokoll](docs/RUNTIME_PROBE.md).

1. **Proof of Concept:** Mit einer frei nutzbaren Runtime und einem frei nutzbaren Grafik-Backend Windows-Steam aus Wine starten, das erste Zielspiel herunterladen und den vollständigen Einzelspieler-Speicher-/Neustart-/Ladeablauf nachweisen. Kompatibilität ist bis dahin unbestätigt.
2. **CLI-Orchestrator:** Bottle-Erstellung, Startargumente, Umgebungsvariablen und Logging automatisieren.
3. **Erste macOS-App:** Minimaler UI-Flow für Import, Start und Status.
4. **Runtime-Management:** Mehrere Wine-Builds und Backend-Auswahl abstrahieren.
5. **Weitere Testspiele:** Nach erfolgreichem ersten Nachweis weitere Indie-Games mit unterschiedlichen Engines/APIs testen und Profile speichern.
6. **Persönliche erste Version:** Nach erfolgreichem PoC die Kernabläufe für den Ziel-Mac bereitstellen. Breite Geräteunterstützung, Setup-Assistent, Lizenzhinweise und signierte/notarisierte öffentliche Releases folgen als eigener Release-Schritt.

**Grobe Aufwandsschätzung:** Ein erster technischer Prototyp für den Ziel-Mac ist je nach vorhandenen Builds in Tagen bis wenigen Wochen denkbar. Eine robuste, öffentlich nutzbare Version mit breiter Geräteunterstützung benötigt eher Monate; eine breit kompatible CrossOver-Alternative ist ein längerfristiges Vorhaben.

## 12. Erste konkrete nächste Aufgaben

- [x] Erstes Zielspiel, Einzelspieler-Testumfang und Testplattform festlegen: Brick by Brick, M5 Pro, 24 GB RAM, macOS 27.0.1.
- [ ] Eine Runtime und ein Backend für den PoC auswählen; macOS-Unterstützung und Lizenz-/Weitergabebedingungen prüfen.
- [ ] Windows-Steam und Brick by Brick: Tidy Up the Small Town! (App 5228920) mit einer frei nutzbaren Runtime und einem frei nutzbaren Backend außerhalb unserer App auf dem Ziel-Mac testen; Installation, Spielen, Speichern und Laden nach Neustart dokumentieren.
- [ ] Nach dem ersten erfolgreichen Zielspiel weitere Testspiele mit unterschiedlichen Engines/APIs auswählen.
- [ ] Steam-Katalogabfrage, sichere lokale Schlüsselablage, Fehlerzustände und Cache auf dem Ziel-Mac nachweisen.
- [ ] Launcher-Leerlauf, Start und Bibliotheksaktionen messen; RAM- und Speicherbudgets erst danach festlegen.
- [ ] Aktuelle GPTK-Lizenz und mögliche D3DMetal-Integration gesondert prüfen.
- [ ] Mit einem Swift-Prototyp den Start und die Überwachung von Wine- und Steam-Prozessen prüfen; anschließend die SwiftUI-Oberfläche anbinden.
- [ ] Verzeichnisstruktur und Profilformat definieren.
- [ ] Git-Repository mit MVP-Backlog aufsetzen.

## 13. Langfristige Produktidee

Aus dem Launcher könnte eine **Open-Source-Spieleplattform für Apple Silicon** werden: mit einer gepflegten Kompatibilitätsdatenbank, gemeinsam getesteten Rezepten und automatischer Diagnose. Der Fokus bleibt auf Nutzbarkeit statt auf dem Versuch, jede Windows-Funktion selbst neu zu implementieren.

**Leitgedanke:** *Install less. Configure less. Play more.*

---

*Konzeptstand: 23. Oktober 2026. Technische, rechtliche und Produktannahmen müssen vor der Implementierung und Veröffentlichung anhand der dann geltenden Dokumentation geprüft werden.*
