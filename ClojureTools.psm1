function Get-StringHash($str) {
  $md5 = new-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
  $utf8 = new-object -TypeName System.Text.UTF8Encoding
  return [System.BitConverter]::ToString($md5.ComputeHash($utf8.GetBytes($str)))
}

function IsNewerFile($file1, $file2) {
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

function Invoke-Clojure {
  $InstallDir = $PSScriptRoot
  $Version = "1.10.0.411"
  $ToolsCp = "$InstallDir\clojure-tools-$Version.jar"

  $ErrorActionPreference = "Stop"

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
    if ($arg.StartsWith("-J")) {
      $JvmOpts += $arg.Substring(2)
    } elseif ($arg.StartsWith("-R")) {
      $aliases, $params = $params
      if ($aliases) {
        $ResolveAliases += ":$aliases"
      } else {
        echo "Missing aliases"
        exit 1
      }
    } elseif ($arg.StartsWith("-C")) {
      $aliases, $params = $params
      if ($aliases) {
        $ClassPathAliases += ":$aliases"
      } else {
        echo "Missing aliases"
        exit 1
      }
    } elseif ($arg.StartsWith("-O")) {
      $aliases, $params = $params
      if ($aliases) {
        $JvmAliases += ":$aliases"
      } else {
        echo "Missing aliases"
        exit 1
      }
    } elseif ($arg.StartsWith("-M")) {
      $aliases, $params = $params
      if ($aliases) {
        $MainAliases += ":$aliases"
      } else {
        echo "Missing aliases"
        exit 1
      }
    } elseif ($arg.StartsWith("-A")) {
      $aliases, $params = $params
      if ($aliases) {
        $AllAliases += ":$aliases"
      } else {
        echo "Missing aliases"
        exit 1
      }
    } elseif ($arg -eq "-Sdeps") {
      $DepsData, $params = $params
      if (!($DepsData)) {
        echo "Missing deps"
        exit 1
      }
    } elseif ($arg -eq "-Scp") {
      $ForceCP, $params = $params
      if (!($ForceCP)) {
        echo "Missing path"
        exit 1
      }
    } elseif ($arg -eq "-Spath") {
      $PrintClassPath = $TRUE
    } elseif ($arg -eq "-Sverbose") {
      $Verbose = $TRUE
    } elseif ($arg -eq "-Sdescribe") {
      $Describe = $TRUE
    } elseif ($arg -eq "-Sforce") {
      $Force = $TRUE
    } elseif ($arg -eq "-Srepro") {
      $Repro = $TRUE
    } elseif ($arg -eq "-Stree") {
      $Tree = $TRUE
    } elseif ($arg -eq "-Spom") {
      $Pom = $TRUE
    } elseif ($arg -eq "-Sresolve-tags") {
      $ResolveTags = $TRUE
    } elseif ($arg.StartsWith("-S")) {
      echo "Invalid option: $arg"
      exit 1
    } elseif (($arg -eq "-h") -or ($arg -eq "--help") -or ($arg -eq "-?")) {
      if ($MainAliases.count -gt 0 -or $AllAliases.count -gt 0) {
        $ClojureArgs += @($arg) + $params
        break
      } else {
        $Help = $TRUE
      }
    } else {
      $ClojureArgs += @($arg) + $params
      break
    }
  }

  $JavaCmd = (Get-Command java.exe -ErrorAction SilentlyContinue).Path
  if (!$JavaCmd) {
    if ($env:JAVA_HOME -and (Test-Path $env:JAVA_HOME)) {
      $JavaCmd = "$JAVA_HOME\bin\java.exe"
    } else {
      echo "Couldn't find 'java'. Please set JAVA_HOME."
      exit 1
    }
  }

  if ($Help) {
    echo "
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
"
    exit 0
  }

  $ToolsCP = "$InstallDir\clojure-tools-$Version.jar"

  if ($ResolveTags) {
    if (Test-Path deps.edn) {
      & "$JavaCmd" -classpath "$ToolsCP" clojure.main -m clojure.tools.deps.alpha.script.resolve-tags "--deps-file=deps.edn"
      exit 0
    } else {
      echo "deps.edn does not exist"
      exit 1
    }
  }

  $ConfigDir = "$env:USERPROFILE\.clojure"
  if (!(Test-Path "$ConfigDir")) {
    New-Item -Type Directory "$ConfigDir" | Out-Null
  }

  if (!(Test-Path "$ConfigDir\deps.edn")) {
    Copy-Item "$InstallDir\example-deps.edn" "$ConfigDir\deps.edn"
  }

  $UserCacheDir = "$ConfigDir\.cpcache"
  if ($Repro) {
    $ConfigPaths = @("$InstallDir\deps.edn", "deps.edn")
  } else {
    $ConfigPaths = @("$InstallDir\deps.edn", "$ConfigDir\deps.edn", "deps.edn")
  }
  $ConfigStr = $ConfigPaths -join ','

  if (Test-Path "deps.edn") {
    $CacheDir = ".cpcache"
  } else {
    $CacheDir = "$UserCacheDir"
  }

  $CK = "$($ResolveAliases -join '')|$($ClassPathAliases -join '')|$($AllAliases -join '')|$($JvmAliases -join '')|$($MainAliases -join '')|$DepsData|$($ConfigPaths -join '|')"
  $CK = (Get-StringHash $CK) -replace '-', ''

  $LibsFile = "$CacheDir\$CK.libs"
  $CpFile = "$CacheDir\$CK.cp"
  $JvmFile = "$CacheDir/$CK.jvm"
  $MainFile = "$CacheDir/$CK.main"

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

  $Stale = $FALSE
  if ($Force -or !(Test-Path $CpFile)) {
    $Stale = $TRUE
  } else {
    foreach ($ConfigPath in $ConfigPaths) {
      if (IsNewerFile $ConfigPath $CpFile) {
        $Stale = $TRUE
        break
      }
    }
  }

  if ($Stale -or $Pom) {
    $ToolsArgs = @()
    if ($DepsData) {
      $ToolsArgs += "--config-data"
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
      $ToolsArgs += "--skip-cp"
    }
  }

  if ($Stale) {
    if ($Verbose) {
      Write-Host "Refreshing classpath"
    }
    & $JavaCmd -Xmx256m -classpath $ToolsCp clojure.main -m clojure.tools.deps.alpha.script.make-classpath --config-files $ConfigStr --libs-file $LibsFile --cp-file $CpFile --jvm-file $JvmFile --main-file $MainFile @ToolsArgs
  }

  if ($ForceCp) {
    $CP = $ForceCp
  } else {
    $CP = Get-Content $CpFile
  }

  if ($Pom) {
    & $JavaCmd -Xmx256m -classpath $ToolsCp clojure.main -m clojure.tools.deps.alpha.script.generate-manifest --config-files=$ConfigStr --gen=pom @ToolsArgs
  } elseif ($PrintClassPath) {
    Write-Host $CP
  } elseif ($Describe) {
    foreach ($ConfigPath in $ConfigPaths) {
      if (Test-Path $ConfigPath) {
        $PathVector = "$PathVector`"$ConfigPath`" "
      }
    }
    Write-Output @"
{:version "$Version"
 :config-files [$PathVector]
 :install-dir $InstallDir
 :config-dir $ConfigDir
 :cache-dir $CacheDir
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
      $JvmCacheOpts = Get-Content $JvmFile
    }
    if (Test-Path $MainFile) {
      $MainCacheOpts = Get-Content $MainFile
    }
    & $JavaCmd @JvmCacheOpts @JvmOpts "-Dclojure.libfile=$LibsFile" -classpath $CP clojure.main @MainCacheOpts @ClojureArgs
  }
}

New-Alias -Name clj -Value Invoke-Clojure
New-Alias -Name clojure -Value Invoke-Clojure
