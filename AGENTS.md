# Agent instructions for VN Reader

## Localization

The UI ships in Traditional Chinese (source), English, Simplified Chinese and Japanese.

- Put every user-facing string in `App/Sources/Shared/L10n.swift` (or next to its use) as
  `String(localized: "area.name", defaultValue: "繁體中文")`. Never put Chinese or Japanese text
  directly in a SwiftUI literal such as `Text("…")`.
- In the same change, add the key to `App/Resources/Localizable.xcstrings` with `en`, `zh-Hans` and
  `ja` values marked `translated`. Keep the format specifiers of the zh-Hant value (`%lld`, `%@`,
  positional `%1$@` when there are several); use a `plural` variation where English needs one.
- Text that must stay the same in every language, such as licence texts, uses `Text(verbatim:)`.
- Do not join localized pieces with full-width punctuation (`，`, `：`, `（）`); put the whole sentence
  in one localized format instead.
- Run `scripts/check-localization.py` before finishing. CI runs it on every push, and a Claude Code
  Stop hook (`.claude/settings.json`) runs it when a session stops.
