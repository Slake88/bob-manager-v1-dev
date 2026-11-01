param(
  [Parameter(Mandatory = $true)][string]$BaseUrl,
  [Parameter(Mandatory = $true)][string]$PublicKeyFile,
  [Parameter(Mandatory = $true)][string]$CredentialAPath,
  [Parameter(Mandatory = $true)][string]$CredentialBPath,
  [Parameter(Mandatory = $true)][string]$DbContainerId
)

$ErrorActionPreference = 'Stop'
$uri = [Uri]$BaseUrl
if ($uri.Scheme -ne 'http' -or $uri.Host -notin @('127.0.0.1', 'localhost', '::1') -or $uri.Port -ne 19402) {
  throw 'BLOCKED: this test runner only permits the approved local API on port 19402.'
}
if ($DbContainerId -ne '421321e939c70ab523f92cc9c210ff3da8970323b7647459074dbab06c610787') {
  throw 'BLOCKED: PostgreSQL container ID does not match the authorized test copy.'
}
$context = (& docker context show 2>$null).Trim()
if ($context -ne 'desktop-linux') { throw 'BLOCKED: Docker context is not the approved local Desktop context.' }
$endpoint = (& docker context inspect $context --format '{{.Endpoints.docker.Host}}' 2>$null).Trim()
if ($endpoint -ne 'npipe:////./pipe/dockerDesktopLinuxEngine') { throw 'BLOCKED: Docker endpoint is not the local Windows Desktop engine.' }
$db = (& docker inspect $DbContainerId 2>$null | ConvertFrom-Json)[0]
if ($db.Id -ne $DbContainerId -or $db.Name -ne '/bob_rc1_authcopy_db_23f4ec393cec' -or
    $db.State.Status -ne 'running' -or $db.Mounts.Count -ne 1 -or
    $db.Mounts[0].Name -ne 'bob_rc1_authcopy_data_23f4ec393cec' -or
    $db.NetworkSettings.Networks.PSObject.Properties.Name -notcontains 'bob_rc1_authcopy_net_23f4ec393cec' -or
    @($db.HostConfig.PortBindings.PSObject.Properties | Where-Object { $_.Value -and $_.Value.Count -gt 0 }).Count -ne 0) {
  throw 'BLOCKED: PostgreSQL container, volume, network or published-port guard failed.'
}
$testNetwork = (& docker network inspect bob_rc1_authcopy_net_23f4ec393cec 2>$null | ConvertFrom-Json)[0]
if (-not $testNetwork.Internal) { throw 'BLOCKED: authorized test network is not internal.' }

$config = Get-Content -LiteralPath $PublicKeyFile -Raw | ConvertFrom-Json
$apiKey = [string]$config.SUPABASE_PUBLISHABLE_KEY
if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'BLOCKED: local public API key is missing.' }

$handler = [System.Net.Http.HttpClientHandler]::new()
$handler.UseProxy = $false
$client = [System.Net.Http.HttpClient]::new($handler)
$client.Timeout = [TimeSpan]::FromSeconds(15)

function Invoke-LocalApi {
  param(
    [Parameter(Mandatory = $true)][string]$Method,
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$Token,
    [object]$Body,
    [string]$Prefer
  )
  $request = [System.Net.Http.HttpRequestMessage]::new(
    [System.Net.Http.HttpMethod]::new($Method),
    "$($uri.AbsoluteUri.TrimEnd('/'))$Path"
  )
  [void]$request.Headers.TryAddWithoutValidation('apikey', $apiKey)
  [void]$request.Headers.TryAddWithoutValidation('Accept-Profile', 'public')
  if ($Token) { [void]$request.Headers.TryAddWithoutValidation('Authorization', "Bearer $Token") }
  if ($Prefer) { [void]$request.Headers.TryAddWithoutValidation('Prefer', $Prefer) }
  if ($null -ne $Body) {
    [void]$request.Headers.TryAddWithoutValidation('Content-Profile', 'public')
    $json = ConvertTo-Json -InputObject $Body -Depth 10 -Compress
    $request.Content = [System.Net.Http.StringContent]::new($json, [Text.Encoding]::UTF8, 'application/json')
  }
  try {
    $response = $client.SendAsync($request).GetAwaiter().GetResult()
    $text = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    return [pscustomobject]@{ Status = [int]$response.StatusCode; Body = $text }
  } finally {
    $request.Dispose()
    if ($response) { $response.Dispose() }
  }
}

function Assert-Test([bool]$Condition, [string]$Name) {
  if (-not $Condition) { throw "FAIL: $Name" }
  Write-Output "PASS: $Name"
}

function Get-SyntheticSession([string]$Path) {
  $credential = Import-Clixml -LiteralPath $Path
  if ($credential -isnot [System.Management.Automation.PSCredential] -or
      $credential.UserName -notmatch '@local\.invalid$') {
    throw 'BLOCKED: test identity must be a saved synthetic @local.invalid PSCredential.'
  }
  $payload = @{ email = $credential.UserName; password = $credential.GetNetworkCredential().Password }
  $response = Invoke-LocalApi -Method 'POST' -Path '/auth/v1/token?grant_type=password' -Body $payload
  if ($response.Status -ne 200) { throw 'BLOCKED: local Auth password grant did not return HTTP 200.' }
  $session = $response.Body | ConvertFrom-Json
  if ([string]::IsNullOrWhiteSpace([string]$session.access_token) -or
      [string]::IsNullOrWhiteSpace([string]$session.user.id)) {
    throw 'BLOCKED: local Auth response did not include an authenticated user session.'
  }
  return [pscustomobject]@{
    Id = [string]$session.user.id
    Token = [string]$session.access_token
    CredentialPath = $Path
  }
}

$a = $null
$b = $null
$testIds = @()
try {
  $a = Get-SyntheticSession -Path $CredentialAPath
  $b = Get-SyntheticSession -Path $CredentialBPath
  if ($a.Id -eq $b.Id) { throw 'BLOCKED: test identities must be distinct.' }
  $testIds = @($a.Id, $b.Id)
  Assert-Test $true 'Auth real: dois utilizadores sintéticos distintos receberam sessão JWT local'

  $canonical = @('dashboard','activity','members','treasury','financial','fees','lottery','events','weekly_officer','agenda','bar','inventory','documents','communication','reports','settings','emergency')
  $orderA = @('bar') + @($canonical | Where-Object { $_ -ne 'bar' })
  $orderB = @('fees') + @($canonical | Where-Object { $_ -ne 'fees' })
  $baseTable = '/rest/v1/user_module_preferences'

  foreach ($user in @(@{ Session = $a; Order = $orderA }, @{ Session = $b; Order = $orderB })) {
    $response = Invoke-LocalApi -Method 'POST' -Path "$baseTable`?on_conflict=user_id" -Token $user.Session.Token -Prefer 'resolution=merge-duplicates,return=representation' -Body @{ user_id = $user.Session.Id; module_order = $user.Order }
    if ($response.Status -notin @(200, 201)) { throw 'FAIL: authorized preference upsert was rejected.' }
  }
  Assert-Test $true 'cada utilizador guardou uma ordem própria pela API'

  $readA = (Invoke-LocalApi -Method 'GET' -Path "$baseTable`?select=user_id,module_order&user_id=eq.$($a.Id)" -Token $a.Token).Body | ConvertFrom-Json
  $readB = (Invoke-LocalApi -Method 'GET' -Path "$baseTable`?select=user_id,module_order&user_id=eq.$($b.Id)" -Token $b.Token).Body | ConvertFrom-Json
  Assert-Test ($readA.Count -eq 1 -and $readA[0].module_order[0] -eq 'bar') 'A lê a sua preferência persistida'
  Assert-Test ($readB.Count -eq 1 -and $readB[0].module_order[0] -eq 'fees') 'B lê uma ordem diferente persistida'

  $logoutA = Invoke-LocalApi -Method 'POST' -Path '/auth/v1/logout' -Token $a.Token
  $logoutB = Invoke-LocalApi -Method 'POST' -Path '/auth/v1/logout' -Token $b.Token
  Assert-Test ($logoutA.Status -in @(200, 204) -and $logoutB.Status -in @(200, 204)) 'logout Auth das duas sessões sintéticas'
  $a = Get-SyntheticSession -Path $a.CredentialPath
  $b = Get-SyntheticSession -Path $b.CredentialPath
  $readAAgain = (Invoke-LocalApi -Method 'GET' -Path "$baseTable`?select=user_id,module_order&user_id=eq.$($a.Id)" -Token $a.Token).Body | ConvertFrom-Json
  $readBAgain = (Invoke-LocalApi -Method 'GET' -Path "$baseTable`?select=user_id,module_order&user_id=eq.$($b.Id)" -Token $b.Token).Body | ConvertFrom-Json
  Assert-Test ($readAAgain.Count -eq 1 -and $readAAgain[0].module_order[0] -eq 'bar' -and $readBAgain.Count -eq 1 -and $readBAgain[0].module_order[0] -eq 'fees') 'as duas ordens persistem após logout e novo login Auth'

  $crossRead = (Invoke-LocalApi -Method 'GET' -Path "$baseTable`?select=user_id,module_order&user_id=eq.$($b.Id)" -Token $a.Token).Body | ConvertFrom-Json
  Assert-Test ($crossRead.Count -eq 0) 'A não lê a preferência de B'

  $crossUpdate = Invoke-LocalApi -Method 'PATCH' -Path "$baseTable`?user_id=eq.$($b.Id)" -Token $a.Token -Prefer 'return=representation' -Body @{ module_order = @('emergency') }
  $crossDelete = Invoke-LocalApi -Method 'DELETE' -Path "$baseTable`?user_id=eq.$($b.Id)" -Token $a.Token -Prefer 'return=representation'
  $readBAfter = (Invoke-LocalApi -Method 'GET' -Path "$baseTable`?select=user_id,module_order&user_id=eq.$($b.Id)" -Token $b.Token).Body | ConvertFrom-Json
  Assert-Test ($crossUpdate.Status -in @(200, 204) -and $crossUpdate.Body -in @('', '[]') -and $crossDelete.Status -in @(200, 204) -and $crossDelete.Body -in @('', '[]') -and $readBAfter.Count -eq 1 -and $readBAfter[0].module_order[0] -eq 'fees') 'A não altera nem elimina a preferência de B'

  $crossInsert = Invoke-LocalApi -Method 'POST' -Path $baseTable -Token $a.Token -Prefer 'return=representation' -Body @{ user_id = $b.Id; module_order = @('emergency') }
  $afterInsert = (Invoke-LocalApi -Method 'GET' -Path "$baseTable`?select=user_id,module_order&user_id=eq.$($b.Id)" -Token $b.Token).Body | ConvertFrom-Json
  Assert-Test ($crossInsert.Status -in @(401, 403) -and $afterInsert.Count -eq 1 -and $afterInsert[0].module_order[0] -eq 'fees') 'A não insere uma preferência em nome de B'

  $anonRead = Invoke-LocalApi -Method 'GET' -Path "$baseTable`?select=user_id,module_order"
  Assert-Test ($anonRead.Status -in @(401, 403)) 'anon não lê preferências'

  $rlsSql = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'user_module_preferences_rls.sql'))
  $dockerArgs = @(
    'exec', '-i', $DbContainerId, 'psql', '-U', 'postgres', '-d', 'postgres',
    '-X', '-v', 'ON_ERROR_STOP=1', '--set', "user_a=$($a.Id)", '--set', "user_b=$($b.Id)"
  )
  $rlsOutput = $rlsSql | & docker @dockerArgs 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0 -or $rlsOutput -notmatch 'PASS: RLS own-row isolation') {
    throw 'FAIL: transactional SQL RLS test did not complete successfully.'
  }
  Assert-Test $true 'SQL RLS: cada UID só opera na própria linha; inserção cruzada recusada; rollback confirmado'
} finally {
  if ($a) {
    try { [void](Invoke-LocalApi -Method 'DELETE' -Path "/rest/v1/user_module_preferences?user_id=eq.$($a.Id)" -Token $a.Token -Prefer 'return=minimal') } catch {}
  }
  if ($b) {
    try { [void](Invoke-LocalApi -Method 'DELETE' -Path "/rest/v1/user_module_preferences?user_id=eq.$($b.Id)" -Token $b.Token -Prefer 'return=minimal') } catch {}
  }
  if ($a -and $b) {
    try {
      $remainingA = (Invoke-LocalApi -Method 'GET' -Path "/rest/v1/user_module_preferences?select=user_id&user_id=eq.$($a.Id)" -Token $a.Token).Body | ConvertFrom-Json
      $remainingB = (Invoke-LocalApi -Method 'GET' -Path "/rest/v1/user_module_preferences?select=user_id&user_id=eq.$($b.Id)" -Token $b.Token).Body | ConvertFrom-Json
      if ($remainingA.Count -eq 0 -and $remainingB.Count -eq 0) {
        Write-Output 'CLEANUP PASS: não ficaram linhas de teste nas preferências.'
      } else {
        Write-Output 'CLEANUP FAIL: foram detetadas linhas de teste remanescentes.'
      }
    } catch {
      Write-Output 'CLEANUP BLOCKED: não foi possível confirmar a remoção das linhas de teste.'
    }
  }
  if ($a) {
    try { [void](Invoke-LocalApi -Method 'POST' -Path '/auth/v1/logout' -Token $a.Token) } catch {}
  }
  if ($b) {
    try { [void](Invoke-LocalApi -Method 'POST' -Path '/auth/v1/logout' -Token $b.Token) } catch {}
  }
  $client.Dispose()
  $handler.Dispose()
}
