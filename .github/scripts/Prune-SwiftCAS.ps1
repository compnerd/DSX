# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

param([Parameter(Mandatory)]
      [string] $Path,

      [Parameter(Mandatory)]
      [long] $SizeLimit)

$ErrorActionPreference = "Stop"

function Find-SwiftScanLibrary() {
  $command = Get-Command swiftc -CommandType Application |
      Select-Object -First 1
  $executable = [IO.Path]::GetFullPath($command.Source)
  $directory = [IO.Path]::GetDirectoryName($executable)
  $root = [IO.Directory]::GetParent($directory).FullName

  $names = @(
    "_InternalSwiftScan.dll"
    "lib_InternalSwiftScan.dylib"
    "lib_InternalSwiftScan.so"
  )
  $locations = @(
    $directory
    [IO.Path]::Combine($root, "lib")
    [IO.Path]::Combine($root, "lib", "swift", "host")
  )

  $information = & $executable -print-target-info
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to query Swift target information"
  }
  $target = ConvertFrom-Json ($information -join [Environment]::NewLine)
  $resource = [string]$target.paths.runtimeResourcePath
  if ($resource) {
    $locations += [IO.Path]::Combine($resource, "host")
    $locations += [IO.Directory]::GetParent($resource).FullName
  }

  foreach ($location in $locations) {
    foreach ($name in $names) {
      $candidate = [IO.Path]::Combine($location, $name)
      if ([IO.File]::Exists($candidate)) {
        return [IO.Path]::GetFullPath($candidate)
      }
    }
  }
  throw "Unable to locate the Swift dependency scanner for $executable"
}

$library = Find-SwiftScanLibrary
$libraryLiteral = $library.Replace('"', '""')

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class SwiftScanCAS {
  [StructLayout(LayoutKind.Sequential)]
  public struct StringRef {
    public IntPtr Data;
    public UIntPtr Length;
  }

  [DllImport(@"$libraryLiteral", CallingConvention = CallingConvention.Cdecl)]
  public static extern IntPtr swiftscan_cas_options_create();

  [DllImport(@"$libraryLiteral", CallingConvention = CallingConvention.Cdecl)]
  public static extern void swiftscan_cas_options_dispose(IntPtr options);

  [DllImport(@"$libraryLiteral", CallingConvention = CallingConvention.Cdecl)]
  public static extern void
  swiftscan_cas_options_set_ondisk_path(IntPtr options,
                                        [MarshalAs(UnmanagedType.LPUTF8Str)]
                                        string path);

  [DllImport(@"$libraryLiteral", CallingConvention = CallingConvention.Cdecl)]
  public static extern IntPtr
  swiftscan_cas_create_from_options(IntPtr options, out StringRef error);

  [DllImport(@"$libraryLiteral", CallingConvention = CallingConvention.Cdecl)]
  public static extern long
  swiftscan_cas_get_ondisk_size(IntPtr cas, out StringRef error);

  [DllImport(@"$libraryLiteral", CallingConvention = CallingConvention.Cdecl)]
  [return: MarshalAs(UnmanagedType.I1)]
  public static extern bool
  swiftscan_cas_set_ondisk_size_limit(IntPtr cas, long sizeLimit,
                                      out StringRef error);

  [DllImport(@"$libraryLiteral", CallingConvention = CallingConvention.Cdecl)]
  [return: MarshalAs(UnmanagedType.I1)]
  public static extern bool
  swiftscan_cas_prune_ondisk_data(IntPtr cas, out StringRef error);

  [DllImport(@"$libraryLiteral", CallingConvention = CallingConvention.Cdecl)]
  public static extern void swiftscan_cas_dispose(IntPtr cas);

  [DllImport(@"$libraryLiteral", CallingConvention = CallingConvention.Cdecl)]
  public static extern void swiftscan_string_dispose(StringRef value);
}
"@

function Get-SwiftScanError([SwiftScanCAS+StringRef] $ErrorRef) {
  if ($ErrorRef.Data -eq [IntPtr]::Zero) { return $null }

  try {
    $length = [int]$ErrorRef.Length.ToUInt64()
    $bytes = [byte[]]::new($length)
    [Runtime.InteropServices.Marshal]::Copy($ErrorRef.Data, $bytes, 0, $length)
    return [Text.Encoding]::UTF8.GetString($bytes)
  } finally {
    [SwiftScanCAS]::swiftscan_string_dispose($ErrorRef)
  }
}

function Assert-SwiftScanSuccess([bool] $Failed,
                                 [SwiftScanCAS+StringRef] $ErrorRef) {
  $message = Get-SwiftScanError $ErrorRef
  if ($Failed) {
    if (!$message) { $message = "SwiftScan CAS operation failed" }
    throw $message
  }
}

function Open-SwiftCAS([IntPtr] $Options, [string] $Path) {
  [SwiftScanCAS]::swiftscan_cas_options_set_ondisk_path($Options, $Path)
  $errorref = [SwiftScanCAS+StringRef]::new()
  $cas = [SwiftScanCAS]::swiftscan_cas_create_from_options($Options, [ref]$errorref)
  $message = Get-SwiftScanError $errorref
  if ($cas -eq [IntPtr]::Zero) {
    if (!$message) { $message = "Unable to open Swift CAS at $Path" }
    throw $message
  }
  return $cas
}

$options = [SwiftScanCAS]::swiftscan_cas_options_create()
if ($options -eq [IntPtr]::Zero) { throw "Unable to create SwiftScan CAS options" }

$cas = [IntPtr]::Zero
try {
  $cas = Open-SwiftCAS $options $Path

  $err = [SwiftScanCAS+StringRef]::new()
  Assert-SwiftScanSuccess `
      ([SwiftScanCAS]::swiftscan_cas_set_ondisk_size_limit($cas, $SizeLimit, [ref]$err)) `
      $err

  $err = [SwiftScanCAS+StringRef]::new()
  $size = [SwiftScanCAS]::swiftscan_cas_get_ondisk_size($cas, [ref]$err)
  Assert-SwiftScanSuccess ($size -eq -2) $err

  # Closing the CAS rotates an oversized primary generation. Garbage only
  # becomes collectible after that rotation has completed.
  [SwiftScanCAS]::swiftscan_cas_dispose($cas)
  $cas = [IntPtr]::Zero
  $cas = Open-SwiftCAS $options $Path

  $err = [SwiftScanCAS+StringRef]::new()
  Assert-SwiftScanSuccess `
      ([SwiftScanCAS]::swiftscan_cas_prune_ondisk_data($cas, [ref]$err)) `
      $err

  $err = [SwiftScanCAS+StringRef]::new()
  $pruned = [SwiftScanCAS]::swiftscan_cas_get_ondisk_size($cas, [ref]$err)
  Assert-SwiftScanSuccess ($pruned -eq -2) $err

  $summary = "Swift CAS maintenance completed at $Path; "
  $summary += "live generations use $pruned bytes "
  $summary += "(previously $size bytes, limit: $SizeLimit bytes)"
  Write-Host $summary
} finally {
  if ($cas -ne [IntPtr]::Zero) { [SwiftScanCAS]::swiftscan_cas_dispose($cas) }
  [SwiftScanCAS]::swiftscan_cas_options_dispose($options)
}
