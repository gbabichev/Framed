# Website maintenance

The user-facing website is a static page in `docs/`, using the cool blue/slate palette and system typography of JustDew’s site. It has no build step, JavaScript dependencies, analytics, external fonts, or bundled Apple artwork. No hosting or release URL has been configured or published by this change.

## Files

- `docs/index.html`: page content and links.
- `docs/styles.css`: responsive layout, colors, and system light/dark appearance.
- `docs/images/`: screenshot assets shared with the user-facing README.

## Screenshot assets

| Asset | Screenshot |
| --- | --- |
| `screen1.png` | Canvas editor with a MacBook frame, headline, and inspector |
| `screen2.png` | Frame Library with previews and device filters |
| `screen3.png` | Export settings and composed preview |

These images are shared by `docs/index.html` and `README.md`. To replace one, update both references and their alt text. Set each website image’s `width` and `height` to its real dimensions; CSS preserves the image’s proportions. The original placeholder SVGs have been removed.

## Preview locally

From the repository root:

```sh
python3 -m http.server 8000 --directory docs --bind 127.0.0.1
```

Open `http://127.0.0.1:8000`. Check desktop and mobile widths and light/dark appearances. Stop the server with Control-C.

For static hosting, publish the contents of `docs/`. On GitHub Pages, this can be the selected branch’s `/docs` folder. Configure the actual host and release destination before adding a public download button or a live Website link to the README. The current page uses working feature and getting-started anchors instead.
