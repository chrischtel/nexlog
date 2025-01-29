# Nexlog

A modern, high-performance logging library for Zig featuring colorized output, file rotation, and comprehensive metadata tracking.

[![Zig](https://img.shields.io/badge/Zig-0.13.0-orange.svg)](https://ziglang.org/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

> Development will mainly happen on the `develop` branch. There is not much documentation. You can look into the `tests/` folder and the `examples/` folder.

## Features

- 🔒 **Thread-safe** by design
- 🎨 **Colorized output** for better readability
- 📁 **File logging** with automatic rotation
- 🔍 **Rich metadata** tracking (timestamp, thread ID, file, line, function)
- ⚡ **High performance** with minimal allocations
- 🛠️ **Builder pattern** for easy configuration
- 🎯 **Multiple log levels** (trace, debug, info, warn, err, critical)

## Quick Start
## Please note that the only examples currently available and up-to-date are in the `examples/` folder.

## Installation

1.
Add Nexlog as a dependency in your `build.zig.zon`:

`zig fetch --save git+https://github.com/chrischtel/nexlog/`

```zig

.{
    .name = "my-project",
    .version = "0.1.0",
    .dependencies = .{
        .nexlog = .{
            // 🚧 Nexlog: Actively Developing
            // Expect rapid feature growth and frequent changes
            // Recommended: Use develop branch for latest improvements
            // "git+https://github.com/chrischtel/nexlog#develop"
            .url = "git+https://github.com/chrischtel/nexlog/",
            .hash = "...",
        },
    },
}
```

2. Add to your `build.zig`:
```zig
    const nexlog = b.dependency("nexlog", .{
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("nexlog", nexlog.module("nexlog"));
```

## Advanced Usage

### Configuration Options

```zig
const config = nexlog.LogConfig{
    .min_level = .info,
    .enable_colors = true,
    .enable_file_logging = true,
    .file_path = "app.log",
    .max_file_size = 10 * 1024 * 1024, // 10MB
    .enable_rotation = true,
    .max_rotated_files = 5,
};
```

### Log Levels

- `trace`: Finest-grained information
- `debug`: Debugging information
- `info`: General information
- `warn`: Warning messages
- `err`: Error messages
- `critical`: Critical failures

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## Building from Source

```bash
git clone https://github.com/chrischtel/nexlog.git
cd nexlog
zig build
```

Run tests:
```bash
zig build test
```

Run examples:
```bash
zig build examples
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Thanks to the Zig community for their support and feedback
- Inspired by great logging libraries across different languages

## Contact

Your Name - [@chrischtel](https://twitter.com/chrischtel)

Project Link: [https://github.com/yourusername/nexlog](https://github.com/chrischtel/nexlog)

---

<p align="center">Made with ❤️ in Zig</p>
