# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
# Read-only failure evidence. None of these observations authorize workflow input.
function Get-FileQuayPickerNativeState($Ui,$Process,[long]$Handle) {
    [FileQuayQualification.ConsumerInput]::Observe($Ui.application,$Ui.main_hwnd,$Process,$Handle)
}
function Get-FileQuayPickerOwner([long]$Handle) {
    @{process_id=[FileQuayQualification.ConsumerInput]::WindowProcess($Handle);
        owner_chain=[FileQuayQualification.ConsumerInput]::OwnerChain($Handle)}
}
function Get-FileQuayPickerProcess([int]$Owner) {Get-Process -Id $Owner -ErrorAction Stop}
function Get-FileQuayPickerRoot([long]$Handle) {[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Handle)}
function Get-FileQuayPickerWalker([ValidateSet('Control','Raw')][string]$View) {
    if ($View -ceq 'Control') {[System.Windows.Automation.TreeWalker]::ControlViewWalker}
    else {[System.Windows.Automation.TreeWalker]::RawViewWalker}
}
function Get-FileQuayPickerDesktopWindows {
    [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
        [System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)
}

function Get-FileQuayPickerDesktopScope($Scope) {
    $windows=@(Get-FileQuayPickerDesktopWindows)
    if ($windows.Count -gt 128) {throw 'Picker diagnostic desktop window budget exceeded.'}
    $matches=[Collections.Generic.List[object]]::new();$zero=0;$errors=0
    foreach ($window in $windows) {
        try {
            $current=$window.Current;$handle=[long]$current.NativeWindowHandle
            if (-not $handle) {$zero++;continue}
            if ($handle -ne $Scope.target_hwnd) {continue}
            $matches.Add(@{process_id_matches=($current.ProcessId -eq $Scope.target_pid);offscreen=$current.IsOffscreen})
        } catch {$errors++}
    }
    @{windows_observed=$windows.Count;zero_handle_roots=$zero;property_error_count=$errors;matching_roots=$matches.ToArray()}
}

function Assert-FileQuayPickerDiagnosticTarget($Scope,$State) {
    $chain=@($State.owner_chain)
    if (-not $State.app_live -or -not $State.main_live -or $State.main_pid -ne $Scope.app_pid -or
        -not $State.target_process_live -or -not $State.target_live -or -not $State.target_visible -or
        $State.target_pid -ne $Scope.target_pid -or $State.target_hwnd -ne $Scope.target_hwnd -or
        $State.foreground_hwnd -ne $Scope.target_hwnd -or $chain.Count -lt 1 -or $chain.Count -gt 8 -or
        $chain[0] -ne $Scope.target_hwnd -or $Scope.main_hwnd -notin $chain -or
        @($chain | Select-Object -Unique).Count -ne $chain.Count) {
        throw 'Picker diagnostic ownership or foreground changed.'
    }
}

function Get-FileQuayPickerCaptureBounds($Bounds,$Desktop) {
    foreach ($rect in @($Bounds,$Desktop)) {
        foreach ($key in @('X','Y','Width','Height')) {
            if (-not [double]::IsFinite([double]$rect.$key)) {throw 'Non-finite picker capture bounds.'}
        }
        if ($rect.Width -lt 1 -or $rect.Height -lt 1) {throw 'Empty picker capture bounds.'}
    }
    $left=[Math]::Floor($Bounds.X);$top=[Math]::Floor($Bounds.Y)
    $right=[Math]::Ceiling($Bounds.X+$Bounds.Width);$bottom=[Math]::Ceiling($Bounds.Y+$Bounds.Height)
    $width=$right-$left;$height=$bottom-$top
    if ($width -gt 8192 -or $height -gt 8192 -or $width*$height -gt 33554432 -or
        $left -lt $Desktop.X -or $top -lt $Desktop.Y -or
        $right -gt $Desktop.X+$Desktop.Width -or $bottom -gt $Desktop.Y+$Desktop.Height) {
        throw 'Picker capture bounds exceed the actual desktop or pixel budget.'
    }
    @{x=[int]$left;y=[int]$top;width=[int]$width;height=[int]$height}
}

function Save-FileQuayPickerDiagnosticScreenshot($Ui,$Scope,[string]$Path) {
    Add-Type -AssemblyName System.Windows.Forms
    $current=$Scope.root.Current
    if ($current.ProcessId -ne $Scope.target_pid -or $current.NativeWindowHandle -ne $Scope.target_hwnd -or $current.IsOffscreen) {
        throw 'Picker capture UIA root does not identify the exact visible native window.'
    }
    $bounds=$current.BoundingRectangle
    $desktop=[System.Windows.Forms.SystemInformation]::VirtualScreen
    $pixels=Get-FileQuayPickerCaptureBounds $bounds $desktop
    $memory=[IO.MemoryStream]::new();$bitmap=$null
    try {
        $bitmap=[Drawing.Bitmap]::new($pixels.width,$pixels.height)
        $graphics=[Drawing.Graphics]::FromImage($bitmap)
        try {
            Assert-FileQuayPickerDiagnosticTarget $Scope (Get-FileQuayPickerNativeState $Ui $Scope.process $Scope.target_hwnd)
            $graphics.CopyFromScreen($pixels.x,$pixels.y,0,0,$bitmap.Size)
            Assert-FileQuayPickerDiagnosticTarget $Scope (Get-FileQuayPickerNativeState $Ui $Scope.process $Scope.target_hwnd)
            $after=$Scope.root.Current.BoundingRectangle
            if ($Scope.root.Current.ProcessId -ne $Scope.target_pid -or $Scope.root.Current.NativeWindowHandle -ne $Scope.target_hwnd -or
                $Scope.root.Current.IsOffscreen -or
                $after.X -ne $bounds.X -or $after.Y -ne $bounds.Y -or $after.Width -ne $bounds.Width -or $after.Height -ne $bounds.Height) {
                throw 'Picker capture ownership or bounds changed during the native screen copy.'
            }
        } finally {$graphics.Dispose()}
        $bitmap.Save($memory,[Drawing.Imaging.ImageFormat]::Png)
        if ($memory.Length -gt 33554432) {throw 'Picker PNG exceeds its byte budget.'}
        $directory=Get-Item -LiteralPath ([IO.Path]::GetDirectoryName($Path)) -Force
        if (-not $directory.PSIsContainer -or $directory.Attributes -band [IO.FileAttributes]::ReparsePoint) {throw 'Picker evidence directory is not a regular directory.'}
        $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try {$memory.Position=0;$memory.CopyTo($stream)} finally {$stream.Dispose()}
        @{name=[IO.Path]::GetFileName($Path);bytes=$memory.Length;sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash;
            pixels_unedited=$true;capture_method='CopyFromScreen';bounds=$pixels;
            desktop=@{x=$desktop.X;y=$desktop.Y;width=$desktop.Width;height=$desktop.Height}}
    } finally {if ($bitmap) {$bitmap.Dispose()};$memory.Dispose()}
}

function Get-FileQuayPickerProviderObservation($Element,$Scope) {
    $current=$Element.Current
    if ($current.ProcessId -ne $Scope.target_pid) {throw 'Picker provider process differs.'}
    $result=[ordered]@{observation_only=$true;properties=[ordered]@{};patterns=[ordered]@{}}
    foreach ($entry in @{native_hwnd='NativeWindowHandle';framework_id='FrameworkId'}.GetEnumerator()) {
        try {$result[$entry.Key]=Limit-FileQuayWorkflowDiagnosticText ([string]$current.($entry.Value))}
        catch {$result[$entry.Key+'_error']=Limit-FileQuayWorkflowDiagnosticText $_.Exception.Message}
    }
    foreach ($entry in ([ordered]@{
        # UIA_ProviderDescriptionPropertyId; older managed clients may not register it.
        provider_description=[System.Windows.Automation.AutomationProperty]::LookupById(30107)
        value_available=[System.Windows.Automation.AutomationElement]::IsValuePatternAvailableProperty
        invoke_available=[System.Windows.Automation.AutomationElement]::IsInvokePatternAvailableProperty
    }).GetEnumerator()) {
        $observation=[ordered]@{};$result.properties[$entry.Key]=$observation
        try {
            $observation.client_property_registered=$null -ne $entry.Value
            if (-not $observation.client_property_registered) {continue}
            $value=$Element.GetCurrentPropertyValue($entry.Value,$true)
            $observation.supported=-not [object]::ReferenceEquals($value,[System.Windows.Automation.AutomationElement]::NotSupported)
            $observation.returned_null=$null -eq $value
            if ($observation.supported -and -not $observation.returned_null) {
                $observation.value=if ($value -is [bool]) {$value} else {Limit-FileQuayWorkflowDiagnosticText ([string]$value)}
            }
        } catch {$observation.error=Limit-FileQuayWorkflowDiagnosticText $_.Exception.Message}
    }
    foreach ($entry in ([ordered]@{Value=[System.Windows.Automation.ValuePattern]::Pattern;Invoke=[System.Windows.Automation.InvokePattern]::Pattern}).GetEnumerator()) {
        $observation=[ordered]@{};$result.patterns[$entry.Key]=$observation
        try {
            $pattern=$null
            $observation.supported=$Element.TryGetCurrentPattern($entry.Value,[ref]$pattern)
            $observation.returned_pattern=$null -ne $pattern
            if ($pattern) {$observation.type=Limit-FileQuayWorkflowDiagnosticText $pattern.GetType().FullName}
            if ($observation.supported -and $observation.returned_pattern -and $entry.Key -ceq 'Value') {
                $observation.is_read_only=$pattern.Current.IsReadOnly
                $observation.value=Limit-FileQuayWorkflowDiagnosticText ([string]$pattern.Current.Value)
            }
        } catch {$observation.error=Limit-FileQuayWorkflowDiagnosticText $_.Exception.Message}
    }
    if ($Element.Current.ProcessId -ne $Scope.target_pid) {throw 'Picker provider process changed during observation.'}
    $result
}

function Get-FileQuayPickerClientAssemblies {[AppDomain]::CurrentDomain.GetAssemblies()}

function Get-FileQuayPickerClientObservation {
    # Observe assemblies already loaded by this client; do not load/register providers.
    $assemblies=@(Get-FileQuayPickerClientAssemblies | Where-Object {
        $_.GetName().Name -in @('UIAutomationClient','UIAutomationTypes','UIAutomationProvider','UIAutomationClientSideProviders')})
    if ($assemblies.Count -gt 16) {throw 'Picker client assembly budget exceeded.'}
    $result=[ordered]@{observation_only=$true;powershell=[string]$PSVersionTable.PSVersion;
        framework=(Limit-FileQuayWorkflowDiagnosticText ([Runtime.InteropServices.RuntimeInformation]::FrameworkDescription));assemblies=@()}
    foreach ($assembly in $assemblies) {
        $result.assemblies+=@{identity=(Limit-FileQuayWorkflowDiagnosticText $assembly.FullName);
            path=(Limit-FileQuayWorkflowDiagnosticText $assembly.Location);mvid=[string]$assembly.ManifestModule.ModuleVersionId}
    }
    $result
}

function Get-FileQuayPickerFailureDiagnostic($Ui) {
    $main=Get-FileQuayPickerNativeState $Ui $Ui.application $Ui.main_hwnd
    if (-not $main.app_live -or -not $main.main_live -or $main.main_pid -ne $Ui.application.Id) {
        throw 'Picker diagnostic retained main ownership is unavailable.'
    }
    $foreground=[long]$main.foreground_hwnd
    $identity=Get-FileQuayPickerOwner $foreground
    $result=[ordered]@{at_utc=[DateTimeOffset]::UtcNow.ToString('O');main_hwnd=$Ui.main_hwnd;app_pid=$Ui.application.Id;
        foreground_hwnd=$foreground;foreground_pid=$identity.process_id;owner_chain=@($identity.owner_chain);
        owned_foreground=$false;observation_only=$true;main_enabled=$main.target_enabled}
    if (-not $foreground -or -not $identity.process_id -or $Ui.main_hwnd -notin $identity.owner_chain) {
        $result.exclusion='Foreground has no native owner chain to the retained main window; UI contents were not read.'
        return $result
    }
    $process=$null
    try {
        $process=Get-FileQuayPickerProcess $identity.process_id
        if ($process.Id -ne $identity.process_id -or $process.HasExited -or $process.SafeHandle.IsInvalid -or $process.SafeHandle.IsClosed) {
            throw 'Picker diagnostic retained process identity is unavailable.'
        }
        $scope=@{app_pid=$Ui.application.Id;main_hwnd=$Ui.main_hwnd;target_pid=$identity.process_id;target_hwnd=$foreground;process=$process}
        Assert-FileQuayPickerDiagnosticTarget $scope (Get-FileQuayPickerNativeState $Ui $process $foreground)
        $scope.root=Get-FileQuayPickerRoot $foreground
        if ($scope.root.Current.ProcessId -ne $scope.target_pid) {throw 'Picker diagnostic UIA root process differs.'}
        $result.owned_foreground=$true
        try {$result.desktop_scope=Get-FileQuayPickerDesktopScope $scope}
        catch {$result.desktop_scope_error=Limit-FileQuayWorkflowDiagnosticText $_.Exception.Message}
        $result.control_tree=@(Get-FileQuayWorkflowObservedTree $scope (Get-FileQuayPickerWalker Control) 80 -IncludePickerProvider)
        Assert-FileQuayPickerDiagnosticTarget $scope (Get-FileQuayPickerNativeState $Ui $process $foreground)
        $result.raw_tree=@(Get-FileQuayWorkflowObservedTree $scope (Get-FileQuayPickerWalker Raw) 80 -IncludePickerProvider)
        Assert-FileQuayPickerDiagnosticTarget $scope (Get-FileQuayPickerNativeState $Ui $process $foreground)
        try {$result.client=Get-FileQuayPickerClientObservation}
        catch {$result.client_error=Limit-FileQuayWorkflowDiagnosticText $_.Exception.Message}
        try {$result.screenshot=Save-FileQuayPickerDiagnosticScreenshot $Ui $scope (Join-Path $Ui.evidence 'consumer-save-picker-failure.png')}
        catch {$result.screenshot_error=Limit-FileQuayWorkflowDiagnosticText $_.Exception.Message}
        $result
    } catch {
        $result.owned_foreground=$false
        foreach ($key in @('control_tree','raw_tree','screenshot')) {$result.Remove($key)}
        $result.observation_error=Limit-FileQuayWorkflowDiagnosticText $_.Exception.Message
        $result
    } finally {if ($process) {$process.Dispose()}}
}
