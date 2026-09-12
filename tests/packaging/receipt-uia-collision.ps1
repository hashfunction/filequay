# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
# This collision is a test input, never a replacement for installed UIA evidence.
if ($IsWindows) {
    Add-Type -Path (Join-Path $PSHOME 'UIAutomationClient.dll')
    $receiptCollisionType=[System.Windows.Automation.ExpandCollapsePattern]
    if ($receiptCollisionType.Assembly.GetName().Name -cne 'UIAutomationClient') {
        throw 'The Windows collision test did not load the real Microsoft UIA client type.'
    }
} else {
    $name=[Reflection.AssemblyName]::new('FileQuayReceiptCollision')
    $assembly=[Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly($name,[Reflection.Emit.AssemblyBuilderAccess]::Run)
    $module=$assembly.DefineDynamicModule('Collision')
    $builder=$module.DefineType('System.Windows.Automation.ExpandCollapsePattern',[Reflection.TypeAttributes]::Public)
    $null=$builder.DefineField('Pattern',[object],[Reflection.FieldAttributes]'Public,Static')
    $receiptCollisionType=$builder.CreateType()
    $receiptCollisionType.GetField('Pattern').SetValue($null,[object]::new())
    # Populate PowerShell's type resolver before the production script is parsed.
    $receiptCollisionType=[System.Windows.Automation.ExpandCollapsePattern]
}
