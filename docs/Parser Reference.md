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
  "name": "SoundQ",
  "parserType": "regex",
  "parserValue": "SoundQ_v[0-9]+(\\.[0-9]+)+\\.pkg"
}
```

Guidelines:

-   Anchor to product-specific text whenever possible.
-   Avoid generic version expressions on noisy pages.

### Apple App Store pattern

``` text
primarySubtitle":"Version [0-9]+(\.[0-9]+)+
```

------------------------------------------------------------------------

## highest_version

Scans every regex match and returns the highest semantic version.

Useful when:

-   Release history pages list many versions.
-   All matched versions belong to the same product.

Avoid when pages contain unrelated version numbers, SDK versions, dates,
or build numbers.

------------------------------------------------------------------------

# Choosing a Parser

Preference order:

1.  Homebrew JSON (`jq_trim_comma`)
2.  Vendor JSON (`jq`)
3.  Vendor release notes (`regex`)
4.  Apple App Store pages (`regex`)
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
