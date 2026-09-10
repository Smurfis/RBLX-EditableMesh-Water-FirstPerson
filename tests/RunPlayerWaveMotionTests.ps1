param([Parameter(Mandatory = $true)][string]$LuauPath)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$fixture = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'PlayerWaveMotion.spec.luau')
$controller = Get-Content -Raw -LiteralPath (Join-Path $repo 'src/StarterPlayer/StarterPlayerScripts/PlayerWaveMotionController.client.lua')
$config = Get-Content -Raw -LiteralPath (Join-Path $repo 'src/ReplicatedStorage/Modules/WaterConfig.lua')
$source = $fixture.Replace('--[[CONFIG_SOURCE]]', $config).Replace('--[[CONTROLLER_SOURCE]]', $controller)
$target = Join-Path ([IO.Path]::GetTempPath()) ('player-wave-test-' + [guid]::NewGuid().ToString() + '.luau')
try {
    [IO.File]::WriteAllText($target, $source)
    & $LuauPath $target
    if ($LASTEXITCODE -ne 0) { throw 'Player wave motion regression checks failed.' }
} finally {
    Remove-Item -LiteralPath $target
}
