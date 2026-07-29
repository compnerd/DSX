# Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause

param(
  [Parameter(Mandatory = $true)] [string] $Module,
  [Parameter(Mandatory = $true)] [string] $Executable,
  [Parameter(Mandatory = $true)] [string] $Scratch
)

$ErrorActionPreference = "Stop"
$modulepath = (Get-Item -LiteralPath $Module).FullName
$product = (Get-Item -LiteralPath $Executable).FullName
$destination = [IO.Path]::GetDirectoryName($product)
if (Test-Path -LiteralPath $Scratch) {
  throw "Runtime extraction directory already exists: $Scratch"
}
$root = (New-Item -ItemType Directory -Path $Scratch).FullName
$installer = New-Object -ComObject WindowsInstaller.Installer
$database = $installer.OpenDatabase($modulepath, 0)
$view = $database.OpenView(
    "SELECT Data FROM _Streams WHERE Name = 'MergeModule.CABinet'")
$view.Execute()
$record = $view.Fetch()
if (!$record) { throw "Swift merge module has no cabinet" }
$cabinet = [IO.Path]::Combine($root, "runtime.cab")
$output = [IO.File]::Create($cabinet)
try {
  while ($true) {
    $text = $record.ReadStream(1, 65536, 1)
    if (!$text.Length) { break }
    $bytes = [Text.Encoding]::GetEncoding(28591).GetBytes($text)
    $output.Write($bytes, 0, $bytes.Length)
  }
} finally {
  $output.Dispose()
  $view.Close()
}
& expand.exe -F:* $cabinet $root | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Unable to extract Swift runtime cabinet" }
$files = @{}
$view = $database.OpenView("SELECT File, FileName FROM File")
$view.Execute()
while ($record = $view.Fetch()) {
  $name = $record.StringData(2).Split('|')[-1]
  $files[$name] = [IO.Path]::Combine($root, $record.StringData(1))
}
$view.Close()
$headers = & llvm-readobj --file-headers $product
if ($LASTEXITCODE -ne 0) { throw "Unable to inspect $product" }
$architecture = ($headers | Select-String '^Arch: ').Line
$pending = [Collections.Generic.Queue[string]]::new()
$pending.Enqueue($product)
$copied = @{}
while ($pending.Count) {
  $imports = & llvm-readobj --coff-imports $pending.Dequeue()
  if ($LASTEXITCODE -ne 0) { throw "Unable to inspect runtime imports" }
  foreach ($line in $imports) {
    if ($line -match '^  Name: (.+\.dll)$') {
      $name = $Matches[1]
      if ($files.ContainsKey($name) -and !$copied.ContainsKey($name)) {
        $source = $files[$name]
        $headers = & llvm-readobj --file-headers $source
        if ($LASTEXITCODE -ne 0) { throw "Unable to inspect $name" }
        if (($headers | Select-String '^Arch: ').Line -ne $architecture) {
          throw "Swift runtime architecture mismatch: $name"
        }
        $path = [IO.Path]::Combine($destination, $name)
        Copy-Item -LiteralPath $source -Destination $path
        $copied[$name] = $true
        $pending.Enqueue($path)
      } elseif ($name.StartsWith("swift") -and !$copied.ContainsKey($name)) {
        throw "Swift runtime is missing $name"
      }
    }
  }
}
Write-Output "Packaged $($copied.Count) matching Swift runtime libraries"
