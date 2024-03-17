# Decompilation tools for Excessive Speed (Chaos Works)

Set of command line tools and libraries for operations on
Chaos Works proprietary formats. Clean room reverse engineered.

## How to build

Repository was written with `zig 0.12` toolchain in mind.
Project does not have any additional dependencies. To just build the project run:

```shell
zig build -Doptimize=ReleaseSmall
```

Executables are created in `zig-out/bin/` relative to directory containing `build.zig` file.

For additional available commands (steps) run `zig build -h`.

# Standalone executables

## xs-volunpack

Extracts `.vol` archive into a specified directory.

### Usage

```shell
xs-volunpack ./path/to/xs_old.vol ./path/to/dump/directory/
```

## xs-volpack

Packs files from specified directory into a `.vol` archive.

### Usage

```shell
xs-volpack ./path/to/dump/directory/ ./path/to/xs_new.vol
```

Simply unpacking and packing archive back without changes
should result in an identical file. Currently it doesn't,
and Excessive Speed won't run it for unknown reasons. It
might have something to do with offsets being specified in
some other way than by following linked list. Other `.vol`
files give some kind of a hint towards that - table of
contents of some sort.

# To use as a library

## TODO

Expose `xs-tools` namespace with all useful tools as a module. Refactor for that usage.

# Shortcomings

- Only zlib compressed archives supported for now, but
  Excessive Speed doesn't have any other than that.
- Archives have a 64 byte footer that remains a mystery,
  but the game doesn't read it. Thus it is saved when
  unpacking the archive and appended verbatim when
  packing it again.
- Not yet proven to be compatible with Excessive Speed.
  Might be very old zlib or some obscure data dependency.

