<img src="Sources/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="128" alt="Stash icon" />

# Stash <img src="Sources/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@2x.png" width="22" alt="Stash Menubar icon" style="vertical-align: middle; filter: invert(1); mix-blend-mode: lighten;" />

![macOS](https://img.shields.io/badge/macOS-14%2B-black)

[![](https://img.shields.io/badge/한국어로%20보기-informational?style=flat)](README.ko.md)


## ☻ Hello!

**Stash** is a macOS clipboard app that tucks away your text, images, and files.  
Like a squirrel hoarding acorns, it keeps everything you copy so you never lose it — pop it right back out anytime with a single shortcut.

<img src="docs/screenshots/popover-en.png" width="320" alt="Stash popover" />


### <img src="Sources/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@2x.png" width="22" alt="Stash Menubar icon" style="vertical-align: middle; filter: invert(1); mix-blend-mode: lighten;" /> Here's what you can do

- `Auto-stash`: Anything you copy — text, images, files — piles up in your stash automatically.
- `Quick access`: Pull up your stash with a shortcut while typing, without breaking your flow.
- `Fast search`: Got a lot stashed? Search by keyword and find it in a snap.
- `Pin it`: Pin the stuff you use often so it never disappears.
- `Detailed info`: See where each item was copied from, when, character count, image previews, and more.
- `Flexible layout`: Resize and move the stash window however you like — keep it open all the time if you want.


### <img src="Sources/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@2x.png" width="22" alt="Stash Menubar icon" style="vertical-align: middle; filter: invert(1); mix-blend-mode: lighten;" /> When it comes in handy

- Worried your latest copy might disappear, so you paste it into Notes just in case? ⮕ `Just keep copying — it's all saved in your stash.`
- Tired of retyping the same phrases in messages? ⮕ `Look it up in your stash. Search works too.`
- Digging through folders for that meme image again? ⮕ `Copy it once, pin it, done.`
- Copy-pasting back and forth across multiple windows? ⮕ `Just copy it all at once, then paste it all at once.`
- Want to peek at an image you copied? ⮕ `Preview it right from your stash.`
- Need to count characters? ⮕ `Your stash shows the character count for any text you copied.`


## ☻ Getting Started

### <img src="Sources/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@2x.png" width="22" alt="Stash Menubar icon" style="vertical-align: middle; filter: invert(1); mix-blend-mode: lighten;" /> How do I install it?

1. Download `Stash.dmg` from the [GitHub Releases](https://github.com/angar2/stash/releases) page.
2. Open the .dmg and drag Stash.app into your `Applications` folder.
3. On first launch, macOS may block it with an *"unidentified developer"* warning. Unblock it one of two ways:

    - **From Finder**  
      > In your `Applications` folder, *right-click Stash.app → Open* → choose *Open* in the confirmation dialog.

    - **From Terminal**

      ```sh   
      xattr -cr /Applications/Stash.app
      ```

    Once unblocked, it'll launch like any other app from then on.


### <img src="Sources/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@2x.png" width="22" alt="Stash Menubar icon" style="vertical-align: middle; filter: invert(1); mix-blend-mode: lighten;" /> How do I use it?

Once you launch the app, the Stash acorn icon ( <img src="Sources/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@2x.png" width="22" alt="Stash Menubar icon" style="vertical-align: middle; filter: invert(1); mix-blend-mode: lighten;" /> ) shows up in your menu bar. Click it or hit your shortcut to open the stash.

First, just copy things like you normally would.

| Action | Shortcut |
|--------|----------|
| Open stash | `⇧⌘C` |
| Navigate items | `↑↓` or `⌘ ↑↓` or `⇧⌘ ↑↓` |
| Paste right away | `⌘V` |
| Just copy | `⌘C` |
| Pin an item | `⌘P` |
| Delete | `⌘⌫` or `⌥⌘⌫` |

All shortcuts are customizable, and you can use mouse clicks too.


## ☻ Good to Know

### <img src="Sources/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@2x.png" width="22" alt="Stash Menubar icon" style="vertical-align: middle; filter: invert(1); mix-blend-mode: lighten;" /> Is it safe?

Yes — Stash never sends your data anywhere.

- **Local only** — No external server calls. Works the same whether you're online or offline.
- **Sensitive data auto-blocked** — Anything copied from password managers like 1Password or Bitwarden is automatically skipped. Stash detects the system markers these apps attach to the clipboard and filters them out.
- **Ignore specific apps** — Don't want copies from certain apps collected? Add them to the ignore list in `⛯` settings.
- **Where data lives** — Everything is stored in a local folder you choose. Need a backup? Just copy that folder.


### <img src="Sources/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@2x.png" width="22" alt="Stash Menubar icon" style="vertical-align: middle; filter: invert(1); mix-blend-mode: lighten;" /> Let me know!

Found something weird, broken, or a feature you wish Stash had? Drop it on [GitHub Issues](https://github.com/angar2/stash/issues) — no formality needed.

Bug reports get fixed faster with these details:

- macOS version (Sonoma 14 / Sequoia 15 / Tahoe 26)
- Stash version
- What you did and what went wrong


## License

MIT License. See the [LICENSE](LICENSE) file for details.
