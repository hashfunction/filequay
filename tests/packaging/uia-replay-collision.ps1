# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
# Preload real-named types before replay doubles. No native UI is exercised here.
function Initialize-FileQuayUiaReplayCollision([string[]]$Names) {
    if ($IsWindows) {
        Add-Type -Path (Join-Path $PSHOME 'UIAutomationClient.dll')
    } else {
        $assembly=[Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly(
            [Reflection.AssemblyName]::new('FileQuayUiaReplayCollision'),[Reflection.Emit.AssemblyBuilderAccess]::Run)
        $module=$assembly.DefineDynamicModule('Collision')
        foreach ($name in $Names) {
            $builder=$module.DefineType(('System.Windows.Automation.'+$name),[Reflection.TypeAttributes]::Public)
            $null=$builder.CreateType()
        }
    }
    foreach ($name in $Names) {
        $type=('System.Windows.Automation.'+$name) -as [type]
        if ($null -eq $type -or ($IsWindows -and $type.Assembly.GetName().Name -cnotin @('UIAutomationClient','UIAutomationTypes'))) {
            throw "Expected independently loaded UIA collision type: $name"
        }
    }
}
