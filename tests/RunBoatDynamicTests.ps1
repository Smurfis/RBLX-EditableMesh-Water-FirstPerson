param([Parameter(Mandatory = $true)][string]$LuauPath)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
foreach ($case in @(
    @('BoatDynamicAuthority.spec.luau', 'src/ServerScriptService/BoatDynamicAuthority.lua', '--[[AUTHORITY_SOURCE]]'),
    @('BoatWaterInteraction.spec.luau', 'src/StarterPlayer/StarterPlayerScripts/WaterInteractionController.client.lua', '--[[CONTROLLER_SOURCE]]'),
    @('BoatPlatformRider.spec.luau', 'src/StarterPlayer/StarterPlayerScripts/WaterPlatformRiderController.client.lua', '--[[PLATFORM_RIDER_SOURCE]]'),
    @('BoatHelmBoarding.spec.luau', 'src/ServerScriptService/BoatHelmBoarding.lua', '--[[HELM_BOARDING_SOURCE]]')
)) {
    $fixture = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot $case[0])
    $controller = Get-Content -Raw -LiteralPath (Join-Path $repo $case[1])
    $source = $fixture.Replace($case[2], $controller)
    $source = $source.Replace('--[[PROPULSION_SOURCE]]', (Get-Content -Raw -LiteralPath (Join-Path $repo 'src/ReplicatedStorage/Modules/BoatPropulsion.lua')))
    $source = $source.Replace('--[[BOAT_CONFIG_SOURCE]]', (Get-Content -Raw -LiteralPath (Join-Path $repo 'src/ReplicatedStorage/Modules/BoatConfig.lua')))
    $source = $source.Replace('--[[BOAT_DEBUG_SOURCE]]', (Get-Content -Raw -LiteralPath (Join-Path $repo 'src/ReplicatedStorage/Modules/BoatRuntimeDebug.lua')))
    $target = Join-Path ([IO.Path]::GetTempPath()) ('boat-test-' + [guid]::NewGuid().ToString() + '.luau')
    try {
        [IO.File]::WriteAllText($target, $source)
        & $LuauPath $target
        if ($LASTEXITCODE -ne 0) { throw ('Boat regression checks failed: ' + $case[0]) }
    } finally {
        Remove-Item -LiteralPath $target
    }
}
