# Parser Reference

Version Report uses parser types to extract version information from
remote sources.

Each app definition contains:

``` json
{
  "id": "example_app",
  "name": "Example App",
  "parserType": "regex",
  "parserValue": "Version [0-9]+(\\.[0-9]+)+",
  "versionURL": "https://example.com/releases"
}
```

## jq

Use when the source is JSON and the desired value can be read directly.

Example:

``` json
{
  "name": "Granola",
  "parserType": "jq",
  "parserValue": ".production"
}
```

Best for: - Vendor JSON APIs - Simple JSON values

------------------------------------------------------------------------

## jq_trim_comma

Designed primarily for Homebrew cask APIs.

Example:

``` json
{
  "name": "Firefox",
  "parserType": "jq_trim_comma",
  "parserValue": ".version"
}
```

Converts:

    1.2.3,abcdef

to:

    1.2.3

Best for: - Homebrew casks

------------------------------------------------------------------------

## regex

Searches HTML or text for the first matching version.

Example:

``` json
{
  "name": "Adobe Photoshop",
  "parserType": "regex",
  "parserValue": "<h2>[^<]*\\(version [0-9]+(\\.[0-9]+)+\\)</h2>"
}
```

Version Report takes the version from the matched text: the first dotted
version (`28.0`) if there is one, otherwise the first whole number (`27`).

Guidelines:

-   Anchor to product-specific text whenever possible.
-   Avoid generic version expressions on noisy pages.

App Store apps use Apple's lookup API with the `jq` parser and
`.results.0.version` rather than a regex; see [Adding Apps.md](Adding%20Apps.md).

------------------------------------------------------------------------

## highest_version

Scans every regex match and returns the highest semantic version.

Useful when:

-   Download or release-history pages list many versions, including older
    ones. Include product-specific text in the pattern, such as
    `atom-premiere_[0-9]+(\.[0-9]+)*_mac`, which also allows whole-number
    versions.
-   All matched versions belong to the same product.

Avoid when pages contain unrelated version numbers, SDK versions, dates,
or build numbers.

------------------------------------------------------------------------

# Choosing a Parser

Preference order:

1.  Homebrew Cask source (or `jq_trim_comma` for other Homebrew JSON)
2.  Vendor JSON (`jq`)
3.  Vendor release notes (`regex`)
4.  Apple App Store (lookup API with `jq`)
5.  `highest_version` only when appropriate

------------------------------------------------------------------------

# Useful Debug Commands

Search around a known version:

``` bash
curl -fsSL "URL" | grep -o -i '.\{0,120\}1\.2\.3.\{0,120\}'
```

List version-like strings:

``` bash
curl -fsSL "URL" | grep -oE '[0-9]+(\.[0-9]+)+' | sort -u
```

Pretty-print JSON:

``` bash
curl -fsSL "URL" | jq .
```

------------------------------------------------------------------------

# Philosophy

The goal is not merely to extract *a* version number.

The goal is to choose the most stable, maintainable source so Version
Report continues to work even as vendor websites evolve.
