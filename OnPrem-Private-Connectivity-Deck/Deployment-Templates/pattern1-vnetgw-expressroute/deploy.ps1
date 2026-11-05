# Thin wrapper: .\deploy.ps1 [-Action Deploy|Validate|WhatIf|Pause|Resume|Destroy] [other Deploy-Pattern.ps1 parameters]
& "$PSScriptRoot\..\Deploy-Pattern.ps1" -Pattern 1 @args
