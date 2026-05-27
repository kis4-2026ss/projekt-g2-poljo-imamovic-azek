# Projekt-Proposal: KI-generiertes Multiplayer-Spiel auf Roblox

**Team:** Aldin Imamovic (s2410307069), Vahid Azek (s2410307054), Armin Poljo (s2410307081)

**Repository:** https://github.com/ArminTheCoder/RBLX_Game_1

---

## 1. Ziel des Projekts

### 1.1 Worum es geht

Wir wollen ein komplettes Multiplayer-Spiel auf Roblox bauen, bei dem praktisch nichts
von uns selbst kommt. Der Code, die 3D-Modelle, die Texturen, die Sounds, die Musik und
sogar Teile vom Game-Design sollen von verschiedenen KI-Tools generiert werden. Unsere
Rolle reduziert sich aufs Prompten und Aussortieren der brauchbaren Outputs. Auch das
Zusammenstecken (Output einer KI als Input für die nächste verwenden, Assets ins Repo
einsortieren, Glue-Code schreiben) sollen KI-Agents übernehmen, soweit das geht.

Was uns dabei interessiert, ist die Frage:

> **Wie weit kommt man heute mit aktuellen KI-Tools, wenn man wirklich versucht ein
> komplettes Spiel ohne handgeschriebenen Code und ohne selbstgemachte Assets zu bauen,
> und wo sind die Grenzen?**

### 1.2 Was wir konkret bauen

Ein 3D-Tag-Spiel mit Parkour-Movement, in den Modi 1v1 und 3-/4-Spieler-FFA. Der Twist
ist eine Art umgekehrtes Hot-Potato: ein leuchtendes Objekt spawnt in der Mitte der Map,
und wer es in einer 90-Sekunden-Runde am längsten hält, gewinnt. Mit einem Klick auf den
aktuellen Halter klaut man ihm das Objekt, der Bestohlene wird kurz gestunnt.

Konkret wollen wir am Ende folgende Features im Spiel haben:

**Map / Arena**
- Geschlossene Parkour-Map
- Low-Poly Art-Style

**Movement**
- ein interesantes movement was man aus parkour spielen kennt.

**Tag-Mechanik**
- Click-to-Steal
- 1-2s Stun
- Holder-Glow (Outline durch Wände sichtbar)
- Auto-Pickup wenn das Objekt frei ist

**Round-System**
- 60/90/120s-Rundenmodus, Hold-Time millisekundengenau, Draw-Handling
- Live-Scoreboard, Win-Screen, Auto-Restart-Loop

**Powerups**
- Speed Boost, Double Jump, Wall Spawn, Teleport, Freeze, etc.

**Camera / UI**
- First-Person
- Timer, Score, Powerup-Anzeige

**Audio (sofern wir noch dazu kommen)**
- Movement-SFX
- Pickup/Tag/Stun-SFX
- Musik

**Multiplayer**
- 1v1, 3-Spieler-FFA, 4-Spieler-FFA
- Queue oder Lobby System (sofern wir noch dazu kommen)

### 1.3 Welche KI an welcher Stelle

Pro Bereich nehmen wir das Tool, das aktuell dafür am besten passt:

- **Code und Game-Design (Luau, Server- und Client-Seite):** Claude Code und OpenAI Codex.
- **Assets und Modelle (Texturen, Icons, UI):** TBD.
- **Sound Effects:** TBD.
- **Musik:** TBD.
- **Dokumentation:** Claude Code und OpenAI Codex.

### 1.4 Wie wir validieren

Am Ende muss die Feature-Liste in 1.2 in Roblox Studio durchspielbar sein, mit 2+
Spielern in einem Multi-Client-Test.

---

## 3. Verwendete KI

| Mitglied |      KI      |
|----------|--------------|
| Armin Poljo | Claude Code (Opus 4.7) |
| Aldin Imamovic | Codex (GPT 5.5) |
| Vahid Azek | Codex (GPT 5.5) |
