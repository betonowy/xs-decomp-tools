# Decompilation tools for Excessive Speed (Chaos Works VOL, SPX, SPC)

Set of command line tools and libraries working with Chaos Works proprietary formats. Clean room reverse engineered.

## Why?

I had fun exploring uncharted territory, also uncovering just a tiny bit of Polish game development history to be preserved.

## How to build

Repository was written with `zig 0.12` toolchain in mind. Project does not have any additional dependencies (there is STB, but it's just a git subrepo). To just build the project run:

```shell
zig build -Doptimize=ReleaseSmall
```

Executables are created in `zig-out/bin/` relative to the directory containing `build.zig` file.

For additional available commands (steps) run `zig build -h` .

# Usage

## xs-vol

Unpacking, packing and inspection (verification) of `.vol` archives.

```shell
xs-vol validate file.vol
```

```shell
xs-vol unpack file.vol path/to/vol/dir
```

```shell
xs-vol pack path/to/vol/dir file.vol
```

The `.vol` files are basically a single linked list of zlib compressed chunks. The last chunk is a table of contents which contains an array of entries and a string table containing paths and labels pointed at by those entries. Last 64 bytes of the file contain a footer, which has a checksum, size of all chunks with headers, distance to table of contents, GUIDs for decompression method and probably machine on which it was encoded, timestamp, some flags of unknown purpose and magic sequence at the end.

Despite archive containing a lot of redundant data. The game will not run it unless every entry field contains valid data. Validator performs compatibility checks in case you wish to write your own thing based on this for whatever reason.

Unpacked directories also have a `root.json` file that describes the archive and labels used by the game so that packed archives can be read back by the game. This is specific to this tool since original software was basically lost media the moment the company went out of business somewhere in the very early 2000's.

Archives will not match original binaries exactly, but the game will happily use them. Yes, you can modify those files and change the game's behavior, have fun!

## xs-sprite

Converts CWE sprites to PNG files. Those sprites are named as either SPC or SPX, but despite the similar name, they have little in common with Spectrum 512 file formats. I guess they stand for collision maps and xcolor respectively, but I have no idea what that means exactly. As their headers include a `CWEsprite` name at the beginning, I suspect it's a completely custom domain specific format.

```shell
xs-sprite ./path/to/sprite.spx ./path/to/output/image.png
```

This format uses 8-bit indexed color format with 32-bit or 24-bit pallete with up to 256 entries. There are kind of 2 variations, one is a 8-bit indexed color format and transparent pixels are simply not encoded. Each scanline has a header that specifies the number of sections within that have color data. Scanline can for ex. skip first 20 pixels, write 10 color pixels, skip 30 pixels, write 15 pixels and end the scanline before the end if there are no more non-transparent pixels to write.

Before pallete starts in memory there is also frame data that has engine relevant information such as origin point of a sprite and other values that look like they specify a subregion of an image where there is data, as opposed to borders which may not get color - unnecessary for conversion.

The second variant is exactly the same, but instead of pixels stored as 8-bit indices they are now a 8-bit indices and 8-bit alpha component making it a 16-bit per pixel now.

It's hard to say if I even got this down right. Specific flags in headers are a mystery to me. I just recognize certain combinations of them and apply certain pallete and pixel format for the ones I deciphered. All files from Excessive Speed are compatible. Some of them have strange colors, but it's a minority and don't seem to be used by the game. A leftover from the DOS era maybe?

For more complete specification on how this format works exactly, just look at the code.

# To use as a library

## TODO

Expose `xs-assets` namespace with all useful tools as a module. Refactor with that usage in mind.

# Shortcomings
* Only raw and zlib compressed archives supported for now, but Excessive Speed doesn't have any other than that. I also don't want to pull any other dependencies than zig toolchain itself for no practical reason.

## Some curious things found in the engine code

I really got to learn more about this than I wished to. I don't have anywhere to share it so here it goes.

Very interestingly the game never decompresses sprites into regular rectangular textures. Instead, in their software rendererer, which seems to remember DOS VGA days, despite the game being released in 99' (but it makes sense since they worked on this "title" since 93' even though it was a completely different game back then), they blit those sprites into a framebuffer in the same way it is encoded in the file, which is kind of impressive. Seems very efficient. Especially since their big level sprites (roughly 4k in size) have a lot of empty spaces in them. They only use DX5 for the framebuffer. They update it manually and that's it. It is what it is. 90's polish game dev. At least they used DirectSound the usual way.

One neat piece of curiosity is that despite running in 640x400, the engine internals still think it's running in 320x200 and "try" to draw sprites as such, but double resolution sprites are just hacked in... somehow. I don't want to know. It works fine, just the sprites can only be rendered at even offsets and that's why rendering looks janky. I spent 2 weeks initially trying to inspect sprite rendering interface and dump assets before I managed to unveil why nothing made any sense.
