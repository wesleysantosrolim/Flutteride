import 'dart:io';

abstract class LinuxConfig {
  LinuxConfig._();

  static const String ubuntuVersion = '22.04';

  static const String assetRootfsPath =
      'assets/linux/ubuntu-base-arm64.tar.gz';

  static const String assetPRootPath =
      'assets/bin/proot';

  static const String rootfsUrl =
      'https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04-base-arm64.tar.gz';

  static const String prootAarch64Url =
      'https://raw.githubusercontent.com/termux/proot-distro/master/bin/proot-aarch64';

  static List<String> buildProotArgs({
    required String rootfsPath,
    String currentDirectory = '/root',
  }) {
    final List<String> args = [
      '-r',
      rootfsPath,
      '-b',
      '/dev',
      '-b',
      '/proc',
      '-b',
      '/sys',
      '-0',
      '-w',
      currentDirectory,
    ];

    if (Directory('/sdcard').existsSync()) {
      args.addAll([
        '-b',
        '/sdcard',
      ]);
    } else if (Directory('/storage').existsSync()) {
      args.addAll([
        '-b',
        '/storage',
      ]);
    }

    args.addAll([
      '/usr/bin/env',
      '-i',
      'HOME=/root',
      'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/flutter/bin',
      'TERM=xterm-256color',
      '/bin/bash',
      '--login',
    ]);

    return args;
  }
}