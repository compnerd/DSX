// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

private import Testing

@main
private enum Runner {
  private static func main() async {
    await Testing.__swiftPMEntryPoint() as Never
  }
}
