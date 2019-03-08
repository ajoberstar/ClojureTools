function Get-StringHash($str) {
  $md5 = new-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
  $utf8 = new-object -TypeName System.Text.UTF8Encoding
  return [System.BitConverter]::ToString($md5.ComputeHash($utf8.GetBytes($str)))
}

function Test-NewerFile($file1, $file2) {
  if (!(Test-Path $file1)) {
    return $FALSE
  }
  if (!(Test-Path $file2)) {
    return $TRUE
  }
  $mod1 = (Get-ChildItem $file1).LastWriteTimeUtc
  $mod2 = (Get-ChildItem $file2).LastWriteTimeUtc
  return $mod1 -gt $mod2
}

# https://stackoverflow.com/questions/34559553/create-a-temporary-directory-in-powershell
function Get-TempJarName () {
  $parent = [System.IO.Path]::GetTempPath()
  [string] $guid = [System.Guid]::NewGuid()
  return Join-Path (Get-M2Root) "clojure-path-$($guid).jar"
}

function Get-M2Root () {
  return [io.path]::combine($HOME, ".m2", "repository")
}

# Create a "pathing jar". This is a workaround for Windows when the classpath gets too large 
# to fit on the command-line (which has a limit of 1024 bytes). For the workaround, we generate 
# a jar file consisting of just a manifest file pointing to all of the jar files that would 
# otherwise be specified on the command-line, and then launch java with only the pathing jar 
# on the command-line. Note that per the manifest spec, the entries in the manifest must be 
# relative to the pathing jar, so we create the pathing jar in the user's maven repository root.
function Create-PathingJar ($classpath) {
  [string] $jar = (Get-TempJarName)
  [string] $cleanPath = $classpath -replace ";", " `n " `
                                   -replace "\\", "/" `
                                   -replace " \S+/\.m2/repository/", " "
  [System.IO.FileInfo] $manifestFile = New-TemporaryFile
  try {
    Set-Content -Path $manifestFile.FullName -Value "Class-Path: $cleanPath `n"
    jar cfm $jar $manifestFile.FullName
  } finally {
    Remove-Item $manifestFile
  }
  return $jar
}

function test ($CP) {
  Write-Host (Create-PathingJar $CP)
}

function Invoke-Clojure {
  $ErrorActionPreference = 'Stop'

  # Set dir containing the installed files
  $InstallDir = $PSScriptRoot
  $Version = '1.10.0.414'
  $ToolsCp = "$InstallDir\clojure-tools-$Version.jar"


  # Extract opts
  $PrintClassPath = $FALSE
  $Describe = $FALSE
  $Verbose = $FALSE
  $Force = $FALSE
  $Repro = $FALSE
  $Tree = $FALSE
  $Pom = $FALSE
  $ResolveTags = $FALSE
  $Help = $FALSE
  $JvmOpts = @()
  $ResolveAliases = @()
  $ClasspathAliases = @()
  $JvmAliases = @()
  $MainAliases = @()
  $AllAliases = @()

  $params = $args
  while ($params.Count -gt 0) {
    $arg, $params = $params
    if ($arg.StartsWith('-J')) {
      $JvmOpts += $arg.Substring(2)
    } elseif ($arg.StartsWith('-R')) {
      $aliases, $params = $params
      if ($aliases) {
        $ResolveAliases += ":$aliases"
      }
    } elseif ($arg.StartsWith('-C')) {
      $aliases, $params = $params
      if ($aliases) {
        $ClassPathAliases += ":$aliases"
      }
    } elseif ($arg.StartsWith('-O')) {
      $aliases, $params = $params
      if ($aliases) {
        $JvmAliases += ":$aliases"
      }
    } elseif ($arg.StartsWith('-M')) {
      $aliases, $params = $params
      if ($aliases) {
        $MainAliases += ":$aliases"
      }
    } elseif ($arg.StartsWith('-A')) {
      $aliases, $params = $params
      if ($aliases) {
        $AllAliases += ":$aliases"
      }
    } elseif ($arg -eq '-Sdeps') {
      $DepsData, $params = $params
    } elseif ($arg -eq '-Scp') {
      $ForceCP, $params = $params
    } elseif ($arg -eq '-Spath') {
      $PrintClassPath = $TRUE
    } elseif ($arg -eq '-Sverbose') {
      $Verbose = $TRUE
    } elseif ($arg -eq '-Sdescribe') {
      $Describe = $TRUE
    } elseif ($arg -eq '-Sforce') {
      $Force = $TRUE
    } elseif ($arg -eq '-Srepro') {
      $Repro = $TRUE
    } elseif ($arg -eq '-Stree') {
      $Tree = $TRUE
    } elseif ($arg -eq '-Spom') {
      $Pom = $TRUE
    } elseif ($arg -eq '-Sresolve-tags') {
      $ResolveTags = $TRUE
    } elseif ($arg.StartsWith('-S')) {
      Write-Error "Invalid option: $arg"
      return
    } elseif ($arg -in '-h', '--help', '-?') {
      if ($MainAliases -or $AllAliases) {
        $ClojureArgs += $arg, $params
        break
      } else {
        $Help = $TRUE
      }
    } else {
      $ClojureArgs += $arg, $params
      break
    }
  }

  # Find java executable
  $JavaCmd = (Get-Command java -ErrorAction SilentlyContinue).Path
  if (-not $JavaCmd) {
    $CandidateJavas = "$env:JAVA_HOME\bin\java.exe", "$env:JAVA_HOME\bin\java"
    $JavaCmd = $CandidateJavas | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not ($env:JAVA_HOME -and $JavaCmd)) {
      Write-Error "Couldn't find 'java'. Please set JAVA_HOME."
      return
    }
  }

  if ($Help) {
    Write-Host @'
Usage: clojure [dep-opt*] [init-opt*] [main-opt] [arg*]
        clj     [dep-opt*] [init-opt*] [main-opt] [arg*]

The clojure script is a runner for Clojure. clj is a wrapper
for interactive repl use. These scripts ultimately construct and
invoke a command-line of the form:

java [java-opt*] -cp classpath clojure.main [init-opt*] [main-opt] [arg*]

The dep-opts are used to build the java-opts and classpath:
  -Jopt          Pass opt through in java_opts, ex: -J-Xmx512m
  -Oalias...     Concatenated jvm option aliases, ex: -O:mem
  -Ralias...     Concatenated resolve-deps aliases, ex: -R:bench:1.9
  -Calias...     Concatenated make-classpath aliases, ex: -C:dev
  -Malias...     Concatenated main option aliases, ex: -M:test
  -Aalias...     Concatenated aliases of any kind, ex: -A:dev:mem
  -Sdeps EDN     Deps data to use as the final deps file
  -Spath         Compute classpath and echo to stdout only
  -Scp CP        Do NOT compute or cache classpath, use this one instead
  -Srepro        Use only the local deps.edn (ignore other config files)
  -Sforce        Force recomputation of the classpath (don't use the cache)
  -Spom          Generate (or update existing) pom.xml with deps and paths
  -Stree         Print dependency tree
  -Sresolve-tags Resolve git coordinate tags to shas and update deps.edn
  -Sverbose      Print important path info to console
  -Sdescribe     Print environment and command parsing info as data

init-opt:
  -i, --init path     Load a file or resource
  -e, --eval string   Eval exprs in string; print non-nil values

main-opt:
  -m, --main ns-name  Call the -main function from namespace w/args
  -r, --repl          Run a repl
  path                Run a script from a file or resource
  -                   Run a script from standard input
  -h, -?, --help      Print this help message and exit

For more info, see:
  https://clojure.org/guides/deps_and_cli
  https://clojure.org/reference/repl_and_main
'@
    return
  }

  # Execute resolve-tags command
  if ($ResolveTags) {
    if (Test-Path deps.edn) {
      & $JavaCmd -classpath $ToolsCP clojure.main -m clojure.tools.deps.alpha.script.resolve-tags --deps-file=deps.edn
      return
    } else {
      Write-Error 'deps.edn does not exist'
      return
    }
  }

  # Determine user config directory
  if ($env:CLJ_CONFIG) {
    $ConfigDir = $env:CLJ_CONFIG
  } elseif ($env:HOME) {
    $ConfigDir = "$env:HOME\.clojure"
  } else {
    $ConfigDir = "$env:USERPROFILE\.clojure"
  }

  # If user config directory does not exist, create it
  if (!(Test-Path "$ConfigDir")) {
    New-Item -Type Directory "$ConfigDir" | Out-Null
  }
  if (!(Test-Path "$ConfigDir\deps.edn")) {
    Copy-Item "$InstallDir\example-deps.edn" "$ConfigDir\deps.edn"
  }

  # Determine user cache directory
  if ($env:CLJ_CACHE) {
    $UserCacheDir = $env:CLJ_CACHE
  } else {
    $UserCacheDir = "$ConfigDir\.cpcache"
  }

  # Chain deps.edn in config paths. repro=skip config dir
  if ($Repro) {
    $ConfigPaths = "$InstallDir\deps.edn", 'deps.edn'
  } else {
    $ConfigPaths = "$InstallDir\deps.edn", "$ConfigDir\deps.edn", 'deps.edn'
  }
  $ConfigStr = $ConfigPaths -join ','

  # Determine whether to use user or project cache
  if (Test-Path deps.edn) {
    $CacheDir = '.cpcache'
  } else {
    $CacheDir = $UserCacheDir
  }

  # Construct location of cached classpath file
  $CacheKey = "$($ResolveAliases -join '')|$($ClassPathAliases -join '')|$($AllAliases -join '')|$($JvmAliases -join '')|$($MainAliases -join '')|$DepsData|$($ConfigPaths -join '|')"
  $CacheKeyHash = (Get-StringHash $CacheKey) -replace '-', ''

  $LibsFile = "$CacheDir\$CacheKeyHash.libs"
  $CpFile = "$CacheDir\$CacheKeyHash.cp"
  $JvmFile = "$CacheDir\$CacheKeyHash.jvm"
  $MainFile = "$CacheDir\$CacheKeyHash.main"

  # Print paths in verbose mode
  if ($Verbose) {
    Write-Host @"
version      = $Version
install_dir  = $InstallDir
config_dir   = $ConfigDir
config_paths = $ConfigPaths
cache_dir    = $CacheDir
cp_file      = $CpFile
"@
  }

  # Check for stale classpath file
  $Stale = $FALSE
  if ($Force -or !(Test-Path $CpFile)) {
    $Stale = $TRUE
  } elseif ($ConfigPaths | Where-Object { Test-NewerFile $_ $CpFile }) {
    $Stale = $TRUE
  }

  # Make tools args if needed
  if ($Stale -or $Pom) {
    $ToolsArgs = @()
    if ($DepsData) {
      $ToolsArgs += '--config-data'
      $ToolsArgs += $DepsData
    }
    if ($ResolveAliases) {
      $ToolsArgs += "-R$ResolveAliases"
    }
    if ($ClassPathAliases) {
      $ToolsArgs += "-C$ClassPathAliases"
    }
    if ($JvmAliases) {
      $ToolsArgs += "-J$JvmAliases"
    }
    if ($MainAliases) {
      $ToolsArgs += "-M$MainAliases"
    }
    if ($AllAliases) {
      $ToolsArgs += "-A$AllAliases"
    }
    if ($ForceCp) {
      $ToolsArgs += '--skip-cp'
    }
  }

  # If stale, run make-classpath to refresh cached classpath
  if ($Stale -and (-not $Describe)) {
    if ($Verbose) {
      Write-Host "Refreshing classpath"
    }
    & $JavaCmd -Xmx256m -classpath $ToolsCp clojure.main -m clojure.tools.deps.alpha.script.make-classpath --config-files $ConfigStr --libs-file $LibsFile --cp-file $CpFile --jvm-file $JvmFile --main-file $MainFile $ToolsArgs
    if ($LastExitCode -ne 0) {
      return
    }
  }

  if ($Describe) {
    $CP = ''
  } elseif ($ForceCp) {
    $CP = $ForceCp
  } else {
    $CP = Get-Content $CpFile
  }

  if ($Pom) {
    & $JavaCmd -Xmx256m -classpath $ToolsCp clojure.main -m clojure.tools.deps.alpha.script.generate-manifest --config-files=$ConfigStr --gen=pom @ToolsArgs
  } elseif ($PrintClassPath) {
    Write-Host $CP
  } elseif ($Describe) {
    $PathVector = ($ConfigPaths | ForEach-Object { "`"$_`"" }) -join ' '
    Write-Output @"
{:version "$Version"
 :config-files [$PathVector]
 :install-dir "$InstallDir"
 :config-dir "$ConfigDir"
 :cache-dir "$CacheDir"
 :force $Force
 :repro $Repro
 :resolve-aliases "$($ResolveAliases -join ' ')"
 :classpath-aliases "$($ClasspathAliases -join ' ')"
 :jvm-aliases "$($JvmAliases -join ' ')"
 :main-aliases "$($MainAliases -join ' ')"
 :all-aliases "$($AllAliases -join ' ')"}
"@
  } elseif ($Tree) {
    & $JavaCmd -Xmx256m -classpath $ToolsCp clojure.main -m clojure.tools.deps.alpha.script.print-tree --libs-file $LibsFile
  } else {
    if (Test-Path $JvmFile) {
      # TODO this seems dangerous
      $JvmCacheOpts = (Get-Content $JvmFile) -split '\s+'
    }
    if (Test-Path $MainFile) {
      # TODO this seems dangerous
      $MainCacheOpts = ((Get-Content $MainFile) -split '\s+') -replace '"', '\"'
    }
    $needsPathingJar = ($CP.length -gt 1024)
    if ($needsPathingJar) {
      $jar = Create-PathingJar $CP
      $ClassPathArgs = "-classpath", $jar
    } else {
      $ClassPathArgs = "-classpath", $CP
    }
    try {
      & $JavaCmd @JvmCacheOpts @JvmOpts "-Dclojure.libfile=$LibsFile" @ClassPathArgs clojure.main @MainCacheOpts @ClojureArgs
    } finally {
      if ($needsPathingJar) {
        Remove-Item $jar
      }
    }
  }
}

New-Alias -Name clj -Value Invoke-Clojure
New-Alias -Name clojure -Value Invoke-Clojure
