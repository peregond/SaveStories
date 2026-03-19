$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$venv = Join-Path $PSScriptRoot ".venv"

if (-not (Test-Path $venv)) {
    if (Get-Command py -ErrorAction SilentlyContinue) {
        py -3 -m venv $venv
    } elseif (Get-Command python -ErrorAction SilentlyContinue) {
        python -m venv $venv
    } else {
        throw "Python 3 не найден. Установи Python 3.13+."
    }
}

& "$venv\\Scripts\\python.exe" -m pip install --upgrade pip
& "$venv\\Scripts\\pip.exe" install -r (Join-Path $PSScriptRoot "requirements.txt")

$env:PYTHONPATH = $root
& "$venv\\Scripts\\python.exe" (Join-Path $PSScriptRoot "dimasave_windows\\main.py")
