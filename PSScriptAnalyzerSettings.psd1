@{
    # Practical defaults for SCCM / client scripts.
    # Errors fail CI. Warnings show up but don't block (yet).

    Severity = @('Error', 'Warning', 'Information')

    IncludeDefaultRules = $true

    ExcludeRules = @(
        # Detection/install scripts print to host on purpose for ConfigMgr.
        'PSAvoidUsingWriteHost'

        # Fine in short toolkit scripts. Tighten this up if we grow real modules.
        'PSUseShouldProcessForStateChangingFunctions'

        # BOM yelling is mostly a Windows PowerShell 5.1 / Notepad thing.
        # These scripts are UTF-8 without BOM and that is fine.
        'PSUseBOMForUnicodeEncodedFile'
    )

    Rules = @{
        PSAvoidUsingCmdletAliases = @{
            Enable = $true
        }

        PSAvoidUsingEmptyCatchBlock = @{
            Enable = $true
        }

        PSUseDeclaredVarsMoreThanAssignments = @{
            Enable = $true
        }

        PSAvoidGlobalVars = @{
            Enable = $true
        }

        PSPossibleIncorrectComparisonWithNull = @{
            Enable = $true
        }

        PSUseApprovedVerbs = @{
            Enable = $true
        }
    }
}
