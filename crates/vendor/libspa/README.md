> **Vendored fork** of [libspa 0.8.0 from crates.io](https://crates.io/crates/libspa/0.8.0)
> (tarball sha256 `65f3a4b81b2a2d8c7f300643676202debd1b7c929dbf5c9bb89402ea11d19810`),
> wired in via `[patch.crates-io]` in the workspace `Cargo.toml`.
>
> Upstream 0.8.0 only compiles against PipeWire >= 0.3.65 headers, but Linux
> release builds run in an `ubuntu:22.04` container (PipeWire 0.3.48) so the
> .deb stays installable on Ubuntu 22.04. `src/param/video/raw.rs` is patched
> to build against both old and new headers:
>
> - `VideoInfoRaw::new()` uses zeroed init instead of a field-by-field literal
>   (the `flags` field does not exist pre-0.3.65);
> - `set_flags()`/`flags()` are stubbed to no-op/`NONE`;
> - `set_modifier()`/`modifier()` cast, as the field changed i64 -> u64.
>
> Everything else is byte-identical to the crates.io release. Drop this fork
> when the pipewire/libspa dependencies move to >= 0.10 (upstream gates the
> newer fields behind `v0_3_65` features from that release on).

# libspa [![](https://img.shields.io/crates/v/libspa.svg)](https://crates.io/crates/libspa) [![](https://docs.rs/libspa/badge.svg)](https://docs.rs/libspa)

[libspa](https://pipewire.org) bindings for Rust.

These bindings are providing a safe API that can be used to interface with
[libspa](https://pipewire.org).

## Documentation

See the [crate documentation](https://pipewire.pages.freedesktop.org/pipewire-rs/libspa/).