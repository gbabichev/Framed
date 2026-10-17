# Website maintenance

The user-facing website is a static page in `docs/`, following the structure and visual style of Code’s site. It has no build step, JavaScript dependencies, analytics, external fonts, or bundled Apple artwork. No hosting or release URL has been configured or published by this change.

## Files

- `docs/index.html`: page content and links.
- `docs/styles.css`: responsive layout, colors, and system light/dark appearance.
- `docs/images/`: screenshot assets shared with the user-facing README.

## Replace the screenshot placeholders

| Placeholder | Intended screenshot |
| --- | --- |
| `editor-placeholder.svg` | Main canvas and inspector, preferably with a headline |
| `library-placeholder.svg` | Frame Library with previews and device filters |
| `export-placeholder.svg` | Export settings and the composed preview |

Put the final PNG, JPEG, or WebP files in `docs/images/`. Update their three image paths and alt text in **both** `docs/index.html` and `README.md`. Set each HTML image’s `width` and `height` to its real dimensions; CSS preserves the image’s proportions. Remove the README’s “App screenshots coming soon” line and the placeholder comment in the HTML.

The current SVGs are intentionally square stand-ins, not app screenshots. They contain no device artwork and should be replaced with images you choose to publish. Do not copy screenshots containing private projects, mail, or other personal content from local testing into the public site.

## Preview locally

From the repository root:

```sh
python3 -m http.server 8000 --directory docs --bind 127.0.0.1
```

Open `http://127.0.0.1:8000`. Check desktop and mobile widths and light/dark appearances. Stop the server with Control-C.

For static hosting, publish the contents of `docs/`. On GitHub Pages, this can be the selected branch’s `/docs` folder. Configure the actual host and release destination before adding a public download button or a live Website link to the README. The current page uses working feature and getting-started anchors instead.
