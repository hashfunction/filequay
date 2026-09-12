# Copyright 2026 Trieflow LLC. Licensed under the MIT License.
function Wait-FileQuayWorkflow([scriptblock]$Observe, [string]$Description, [int]$Seconds=30) {
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds); $last = 'No matching observation.'
    while ([DateTime]::UtcNow -lt $deadline) {
        try { $value = & $Observe; if ($null -ne $value -and $value -ne $false) { return $value } }
        catch { $last = $_.Exception.Message }
        Start-Sleep -Milliseconds 100
    }
    throw "Timed out waiting for ${Description}: $last"
}

function Add-FileQuayWorkflowTrace($Ui, [string]$Step, $Details) {
    if ($Ui.record.trace.Count -lt 96) { $Ui.record.trace.Add(@{step=$Step;at_utc=[DateTimeOffset]::UtcNow.ToString('O');details=$Details}) }
}

function Get-FileQuayWorkflowScopes($Ui, [switch]$AllowBroker) {
    if ($Ui.application.HasExited -or $Ui.application.SafeHandle.IsClosed -or $Ui.application.SafeHandle.IsInvalid) { throw 'The retained consumer process exited or its handle is unavailable.' }
    $windows = [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
        [System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
    if ($windows.Count -gt 128) { throw 'Desktop top-level observation exceeded its bounded window budget.' }
    $handles = [Collections.Generic.HashSet[long]]::new()
    foreach ($window in $windows) {
        $handle = [long]$window.Current.NativeWindowHandle
        if ($handle) { $null=$handles.Add($handle) }
    }
    # The owned broker can be absent from UIA desktop children. Native ownership
    # is checked before reading its UIA root, then again after retaining its process.
    $main = [FileQuayQualification.ConsumerInput]::Observe($Ui.application,$Ui.main_hwnd,$Ui.application,$Ui.main_hwnd)
    if (-not $main.app_live -or -not $main.main_live -or $main.main_pid -ne $Ui.application.Id) {
        throw 'The retained consumer main window ownership changed.'
    }
    $foreground = [long]$main.foreground_hwnd
    if ($foreground -and $Ui.main_hwnd -in [FileQuayQualification.ConsumerInput]::OwnerChain($foreground)) {
        $owner = [FileQuayQualification.ConsumerInput]::WindowProcess($foreground)
        if ($owner -eq $Ui.application.Id -or ($owner -gt 0 -and $AllowBroker)) { $null=$handles.Add($foreground) }
    }
    foreach ($handle in $handles) {
        $chain = [FileQuayQualification.ConsumerInput]::OwnerChain($handle)
        if ($Ui.main_hwnd -notin $chain) { continue }
        $owner = [FileQuayQualification.ConsumerInput]::WindowProcess($handle)
        if (-not $owner -or ($owner -ne $Ui.application.Id -and -not $AllowBroker)) { continue }
        $root = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$handle)
        $current = $root.Current
        if ($current.NativeWindowHandle -ne $handle -or $current.ProcessId -ne $owner -or $current.IsOffscreen) { continue }
        $process = $Ui.application
        if ($owner -ne $Ui.application.Id) {
            if (-not $Ui.brokers.ContainsKey([string]$owner)) {
                if ($Ui.brokers.Count -ge 8) { throw 'Native picker process observation exceeded its handle budget.' }
                $candidate = Get-Process -Id $owner
                try {
                    $retained = $candidate.SafeHandle
                    if ($candidate.Id -ne $owner -or $retained.IsInvalid -or $retained.IsClosed -or $candidate.HasExited -or
                        [FileQuayQualification.ConsumerInput]::WindowProcess($handle) -ne $owner -or
                        $Ui.main_hwnd -notin [FileQuayQualification.ConsumerInput]::OwnerChain($handle)) { throw 'Picker ownership changed while retaining its process handle.' }
                    $Ui.brokers[[string]$owner] = $candidate
                } catch { $candidate.Dispose(); throw }
            }
            $process = $Ui.brokers[[string]$owner]
        }
        $state = [FileQuayQualification.ConsumerInput]::Observe($Ui.application,$Ui.main_hwnd,$process,$handle)
        if ($process.Id -ne $owner -or $process.HasExited -or $process.SafeHandle.IsInvalid -or $process.SafeHandle.IsClosed -or
            -not $state.app_live -or -not $state.main_live -or $state.main_pid -ne $Ui.application.Id -or
            -not $state.target_process_live -or -not $state.target_live -or -not $state.target_visible -or
            $state.target_pid -ne $owner -or $state.target_hwnd -ne $handle -or $Ui.main_hwnd -notin $state.owner_chain -or
            ($handle -eq $foreground -and $state.foreground_hwnd -ne $foreground) -or
            $root.Current.NativeWindowHandle -ne $handle -or $root.Current.ProcessId -ne $owner -or $root.Current.IsOffscreen) {
            throw 'Workflow window ownership changed during scope discovery.'
        }
        @{
            app_pid=$Ui.application.Id;main_hwnd=$Ui.main_hwnd;target_pid=[int]$owner;target_hwnd=$handle
            process=$process;root=$root
        }
    }
}

function Get-FileQuayWorkflowMain($Ui) {
    $matches = @(Get-FileQuayWorkflowScopes $Ui | Where-Object target_hwnd -EQ $Ui.main_hwnd)
    if ($matches.Count -ne 1) { throw 'The exact owned main window is absent or ambiguous.' }
    @{scope=$matches[0];element=$matches[0].root}
}

function Get-FileQuayWorkflowElementWindow($Element) {
    $ancestor = $Element
    for ($i=0; $ancestor -and $i -lt 48; $i++) {
        $handle = [long]$ancestor.Current.NativeWindowHandle
        if ($handle) { return [FileQuayQualification.ConsumerInput]::RootWindow($handle) }
        $ancestor = [System.Windows.Automation.TreeWalker]::RawViewWalker.GetParent($ancestor)
    }
    throw 'UI element has no provable native window ancestor.'
}

function Find-FileQuayWorkflowElements($Ui, [string]$Id='', [string]$Name='', $Within=$null, [switch]$AllowBroker, [switch]$IncludeHidden) {
    $condition = [System.Windows.Automation.Condition]::TrueCondition
    if ($Id) { $condition = [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::AutomationIdProperty,$Id) }
    elseif ($Name) { $condition = [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::NameProperty,$Name) }
    $scopes = if ($Within) { @($Within.scope) } else { @(Get-FileQuayWorkflowScopes $Ui -AllowBroker:$AllowBroker) }
    $seen = [Collections.Generic.HashSet[string]]::new()
    foreach ($scope in $scopes) {
        $root = if ($Within) { $Within.element } else { $scope.root }
        $found = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants,$condition)
        if ($found.Count -gt 256) { throw 'Workflow selector exceeded its bounded element budget.' }
        foreach ($element in $found) {
            $current = $element.Current
            if ($current.ProcessId -ne $scope.target_pid) { continue }
            if (-not $IncludeHidden -and ($current.IsOffscreen -or -not $current.IsEnabled)) { continue }
            if ($Name -and $current.Name -cne $Name) { continue }
            $nativeWindow=Get-FileQuayWorkflowElementWindow $element
            $bindingScope=$scope
            if ($nativeWindow -ne $scope.target_hwnd) {
                if ($Ui.main_hwnd -notin [FileQuayQualification.ConsumerInput]::OwnerChain($nativeWindow) -or
                    [FileQuayQualification.ConsumerInput]::WindowProcess($nativeWindow) -ne $scope.target_pid) { continue }
                $bindingScope=@{} + $scope
                $bindingScope.target_hwnd=$nativeWindow
                $bindingScope.root=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$nativeWindow)
            }
            if ($seen.Add([string]::Join(',', [int[]]$element.GetRuntimeId()))) { @{scope=$bindingScope;element=$element} }
        }
    }
}

function Find-FileQuayWorkflowElement($Ui, [string]$Id='', [string]$Name='', $Within=$null, [switch]$AllowBroker, [switch]$IncludeHidden) {
    $found = @(Find-FileQuayWorkflowElements $Ui $Id $Name $Within -AllowBroker:$AllowBroker -IncludeHidden:$IncludeHidden)
    if ($found.Count -ne 1) { throw "Expected one owned workflow element '$Id'/'$Name'; observed $($found.Count)." }
    $found[0]
}

function Get-FileQuayWorkflowTargetState($Ui, $Binding) {
    $scope = $Binding.scope; $element = $Binding.element
    $state = @{}
    foreach ($pair in [FileQuayQualification.ConsumerInput]::Observe($Ui.application,$Ui.main_hwnd,$scope.process,$scope.target_hwnd).GetEnumerator()) { $state[$pair.Key]=$pair.Value }
    $rootId = [string]::Join(',', [int[]]$scope.root.GetRuntimeId())
    $within = $false; $ancestor = $element
    for ($i=0; $ancestor -and $i -lt 48; $i++) {
        if ([string]::Join(',', [int[]]$ancestor.GetRuntimeId()) -ceq $rootId) { $within=$true; break }
        $ancestor = [System.Windows.Automation.TreeWalker]::RawViewWalker.GetParent($ancestor)
    }
    $current = $element.Current
    $state.element_pid=$current.ProcessId; $state.element_within_target=$within
    $state.element_hwnd=Get-FileQuayWorkflowElementWindow $element
    $state.element_visible=-not $current.IsOffscreen; $state.element_enabled=$current.IsEnabled
    $state
}

function Invoke-FileQuayWorkflowAction($Ui, $Binding, [ValidateSet('Invoke','Select','Expand','Collapse','Value','Keys','ScrollUp','ScrollDown')][string]$Action, $Value=$null) {
    $scope=$Binding.scope; $element=$Binding.element
    [FileQuayQualification.ConsumerInput]::Foreground($Ui.application,$Ui.main_hwnd,$scope.process,$scope.target_hwnd)
    $state = Get-FileQuayWorkflowTargetState $Ui $Binding
    Assert-FileQuayWorkflowTarget $scope $state
    Add-FileQuayWorkflowTrace $Ui $Action @{automation_id=$element.Current.AutomationId;name=$element.Current.Name;state=$state}
    switch ($Action) {
        'Invoke' { ([System.Windows.Automation.InvokePattern]$element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)).Invoke() }
        'Select' { ([System.Windows.Automation.SelectionItemPattern]$element.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)).Select() }
        'Expand' { ([System.Windows.Automation.ExpandCollapsePattern]$element.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)).Expand() }
        'Collapse' { ([System.Windows.Automation.ExpandCollapsePattern]$element.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)).Collapse() }
        'Value' { ([System.Windows.Automation.ValuePattern]$element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)).SetValue([string]$Value) }
        { $_ -in @('ScrollUp','ScrollDown') } {
            $direction=if ($Action -eq 'ScrollUp') {[System.Windows.Automation.ScrollAmount]::SmallDecrement} else {[System.Windows.Automation.ScrollAmount]::SmallIncrement}
            ([System.Windows.Automation.ScrollPattern]$element.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern)).Scroll([System.Windows.Automation.ScrollAmount]::NoAmount,$direction)
        }
        'Keys' {
            if ($element.Current.IsKeyboardFocusable) { $element.SetFocus() }
            elseif ([string]::Join(',', [int[]]$element.GetRuntimeId()) -cne [string]::Join(',', [int[]]$scope.root.GetRuntimeId())) {
                throw 'The selected workflow element cannot receive keyboard focus.'
            }
            Assert-FileQuayWorkflowTarget $scope (Get-FileQuayWorkflowTargetState $Ui $Binding)
            [FileQuayQualification.ConsumerInput]::Chord($Ui.application,$Ui.main_hwnd,$scope.process,$scope.target_hwnd,[int[]]$Value)
        }
    }
}

function Invoke-FileQuayWorkflowPaste($Ui, [string]$Description) {
    $ready = Wait-FileQuayWorkflow {
        $commands = @(Find-FileQuayWorkflowElements $Ui 'InnerNavigationToolbarPasteButton')
        if ($commands.Count -gt 1) { throw 'The enabled Paste command is ambiguous.' }
        if ($commands.Count -eq 1) { return @{command=$commands[0];overflow=$null} }
        $main = Get-FileQuayWorkflowMain $Ui
        $bar = Find-FileQuayWorkflowElement $Ui 'ContextCommandBar' -Within $main
        $more = Find-FileQuayWorkflowElement $Ui 'MoreButton' 'More options' -Within $bar
        foreach ($binding in @($bar,$more)) {
            if ($binding.scope.target_pid -ne $Ui.application.Id -or $binding.scope.target_hwnd -ne $Ui.main_hwnd -or
                $binding.element.Current.ProcessId -ne $Ui.application.Id) { throw 'Toolbar overflow is outside the retained main window.' }
        }
        if ($bar.element.Current.ClassName -cne 'ApplicationBar' -or $more.element.Current.ClassName -cne 'Button' -or
            $more.element.Current.Name -cne 'More options') { throw 'The observed toolbar overflow control differs.' }
        @{command=$null;overflow=$more}
    } "$Description or the owned toolbar overflow"
    if ($ready.overflow) {
        # Invoke once, outside the polling loop; a failed provider call must not toggle it again.
        Invoke-FileQuayWorkflowAction $Ui $ready.overflow Invoke
        Add-FileQuayWorkflowClipboardObservation $Ui 'paste-overflow-opened'
        $command = Wait-FileQuayWorkflow {
            Find-FileQuayWorkflowElement $Ui 'InnerNavigationToolbarPasteButton'
        } $Description
    } else { $command=$ready.command }
    Invoke-FileQuayWorkflowAction $Ui $command Invoke
}

function Find-FileQuayWorkflowReceiptElement($Ui, [string]$Name,
    [ValidateSet('ReceiptDetailsExpander','ReceiptSourcePaths','ReceiptDestinationPaths')][string]$Part='ReceiptDetailsExpander') {
    if ([string]::IsNullOrWhiteSpace($Name)) { throw 'Receipt identity requires its exact observed title.' }
    $list=Find-FileQuayWorkflowElement $Ui 'ReceiptHistoryList'
    $card=Find-FileQuayWorkflowElement $Ui 'ReceiptDetailsExpander' $Name -Within $list -IncludeHidden
    if ($Part -ceq 'ReceiptDetailsExpander') { return $card }
    Find-FileQuayWorkflowElement $Ui $Part -Within $card -IncludeHidden
}

function Show-FileQuayWorkflowElement($Ui, [string]$Name,
    [ValidateSet('ReceiptDetailsExpander','ReceiptSourcePaths','ReceiptDestinationPaths')][string]$Part='ReceiptDetailsExpander') {
    $lastUnavailable=$null
    for ($attempt=0; $attempt -lt 16; $attempt++) {
        try {
            # ListView templates can replace both cards and their scroll provider.
            # Reobserve the exact owned card/detail before every scrolling attempt.
            $binding=Find-FileQuayWorkflowReceiptElement $Ui $Name $Part
            if (-not $binding.element.Current.IsOffscreen) { return $binding }
            $ancestor=[System.Windows.Automation.TreeWalker]::RawViewWalker.GetParent($binding.element)
            $container=$null
            for ($i=0; $ancestor -and $i -lt 24; $i++) {
                if ((Get-FileQuayWorkflowElementWindow $ancestor) -ne $binding.scope.target_hwnd) { break }
                $scroll=$null
                if (-not $ancestor.Current.IsOffscreen -and
                    $ancestor.TryGetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern,[ref]$scroll) -and $scroll.Current.VerticallyScrollable) {
                    $container=@{scope=$binding.scope;element=$ancestor}; break
                }
                $ancestor=[System.Windows.Automation.TreeWalker]::RawViewWalker.GetParent($ancestor)
            }
            if (-not $container) { throw 'Offscreen receipt detail has no visible owned scroll container.' }
            $direction=if ($binding.element.Current.BoundingRectangle.Top -lt $container.element.Current.BoundingRectangle.Top) {'ScrollUp'} else {'ScrollDown'}
            Invoke-FileQuayWorkflowAction $Ui $container $direction
        } catch {
            $errorType=$_.Exception;$unavailable=$null
            for ($depth=0; $errorType -and $depth -lt 8; $depth++) {
                if ($errorType -is [System.Windows.Automation.ElementNotAvailableException]) { $unavailable=$errorType;break }
                $errorType=$errorType.InnerException
            }
            if (-not $unavailable) { throw }
            $lastUnavailable=$unavailable
            Add-FileQuayWorkflowTrace $Ui 'ReceiptScrollRequery' @{name=$Name;automation_id=$Part;attempt=($attempt+1);error_type=$unavailable.GetType().FullName}
        }
        Start-Sleep -Milliseconds 100
    }
    throw [InvalidOperationException]::new('The receipt detail did not become visible within the scroll budget.', $lastUnavailable)
}

function Get-FileQuayWorkflowText($Binding) {
    $value = $null
    if ($Binding.element.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern,[ref]$value)) { return $value.Current.Value }
    if ($Binding.element.Current.ControlType -eq [System.Windows.Automation.ControlType]::Text) { return $Binding.element.Current.Name }
    $text = $null
    if ($Binding.element.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern,[ref]$text)) {
        return $text.DocumentRange.GetText(4096)
    }
    $Binding.element.Current.Name
}

function Set-FileQuayWorkflowFolder($Ui, [string]$Path) {
    Invoke-FileQuayWorkflowAction $Ui (Get-FileQuayWorkflowMain $Ui) Keys @(17,76)
    $box = Wait-FileQuayWorkflow { Find-FileQuayWorkflowElement $Ui 'PART_TextBox' } 'visible omnibar path entry'
    Invoke-FileQuayWorkflowAction $Ui $box Value $Path
    Invoke-FileQuayWorkflowAction $Ui $box Keys @(13)
    $null = Wait-FileQuayWorkflow {
        $current = Find-FileQuayWorkflowElement $Ui 'CurrentPathGet' -IncludeHidden
        if ((Get-FileQuayWorkflowText $current).TrimEnd('\') -ine $Path.TrimEnd('\')) { throw 'Observed current folder differs.' }
        $true
    } "navigation to the owned folder $Path"
}

function Select-FileQuayWorkflowFile($Ui, [string]$Path) {
    $leaf = [IO.Path]::GetFileName($Path)
    $binding = Wait-FileQuayWorkflow {
        $matches = @(); $seen=[Collections.Generic.HashSet[string]]::new()
        foreach ($name in @($leaf,[IO.Path]::GetFileNameWithoutExtension($leaf))) {
            foreach ($candidate in @(Find-FileQuayWorkflowElements $Ui -Name $name)) {
                $element=$candidate.element
                for ($i=0; $element -and $i -lt 12; $i++) {
                    if ((Get-FileQuayWorkflowElementWindow $element) -ne $candidate.scope.target_hwnd) { break }
                    $selection=$null
                    if ($element.Current.ControlType -in @([System.Windows.Automation.ControlType]::ListItem,[System.Windows.Automation.ControlType]::DataItem) -and
                        $element.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern,[ref]$selection)) {
                        if ($seen.Add([string]::Join(',', [int[]]$element.GetRuntimeId()))) { $matches += @{scope=$candidate.scope;element=$element} }
                        break
                    }
                    $element=[System.Windows.Automation.TreeWalker]::RawViewWalker.GetParent($element)
                }
            }
        }
        if ($matches.Count -ne 1) { throw "Expected one selectable fixture item; observed $($matches.Count)." }
        $matches[0]
    } 'the uniquely named fixture file'
    Invoke-FileQuayWorkflowAction $Ui $binding Select
    if (-not ([System.Windows.Automation.SelectionItemPattern]$binding.element.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)).Current.IsSelected) {
        throw 'The named fixture item was not selected.'
    }
}

function Open-FileQuayWorkflowHistory($Ui) {
    if (@(Find-FileQuayWorkflowElements $Ui 'ReceiptHistoryTab').Count -eq 0) {
        Invoke-FileQuayWorkflowAction $Ui (Find-FileQuayWorkflowElement $Ui 'ShowStatusCenterButton') Invoke
    }
    $tab = Wait-FileQuayWorkflow { Find-FileQuayWorkflowElement $Ui 'ReceiptHistoryTab' } 'receipt history tab'
    Invoke-FileQuayWorkflowAction $Ui $tab Select
    Wait-FileQuayWorkflow { Find-FileQuayWorkflowElement $Ui 'ReceiptHistoryList' } 'receipt history list'
}

function Read-FileQuayWorkflowVisibleReceipts($Ui, $List, [object[]]$Receipts) {
    $names = @(Wait-FileQuayWorkflow {
        $List=Find-FileQuayWorkflowElement $Ui 'ReceiptHistoryList'
        $found = @(Find-FileQuayWorkflowElements $Ui 'ReceiptDetailsExpander' -Within $List)
        if ($found.Count -ne 2) { throw "Expected two visible receipt cards, observed $($found.Count)." }
        $titles=@($found | ForEach-Object { $_.element.Current.Name })
        if ([string]::IsNullOrWhiteSpace($titles[0]) -or [string]::IsNullOrWhiteSpace($titles[1]) -or $titles[0] -ceq $titles[1]) {
            throw 'The two visible receipt card titles are absent or ambiguous.'
        }
        $titles
    } 'two receipt cards')
    $seen = [Collections.Generic.HashSet[string]]::new()
    $result = @()
    foreach ($name in $names) {
        $card=Show-FileQuayWorkflowElement $Ui $name
        Invoke-FileQuayWorkflowAction $Ui $card Expand
        $null=Wait-FileQuayWorkflow { Find-FileQuayWorkflowReceiptElement $Ui $name 'ReceiptSourcePaths' } 'expanded receipt source'
        $source=Show-FileQuayWorkflowElement $Ui $name 'ReceiptSourcePaths'
        $sourceText=Get-FileQuayWorkflowText $source
        $null=Wait-FileQuayWorkflow { Find-FileQuayWorkflowReceiptElement $Ui $name 'ReceiptDestinationPaths' } 'expanded receipt destination'
        $destination=Show-FileQuayWorkflowElement $Ui $name 'ReceiptDestinationPaths'
        $detail=@{source=$sourceText;destination=(Get-FileQuayWorkflowText $destination)}
        $matches = @($Receipts | Where-Object { $_.sourcePaths[0] -ceq $detail.source -and $_.destinationPaths[0] -ceq $detail.destination })
        if ($matches.Count -ne 1 -or -not $seen.Add($matches[0].id)) { throw 'Visible receipt paths do not identify one distinct persisted operation.' }
        $operation = if ($matches[0].fileOperationType -eq 3) {'Copy'} else {'Move'}
        $expectedTitle = $Ui.strings["ReceiptOperation$operation"] + ' · ' + $Ui.strings.ReceiptResultSuccess
        $card=Find-FileQuayWorkflowReceiptElement $Ui $name
        if ($card.element.Current.Name -cne $expectedTitle) { throw 'Visible receipt operation/result differs.' }
        $result += @{id=$matches[0].id;title=$card.element.Current.Name;source=$detail.source;destination=$detail.destination}
        Invoke-FileQuayWorkflowAction $Ui $card Collapse
    }
    $result
}

function Find-FileQuayWorkflowSaveFilename($Ui) {
    $hostControl = Find-FileQuayWorkflowElement $Ui 'FileNameControlHost' -AllowBroker
    if ($hostControl.scope.target_hwnd -eq $Ui.main_hwnd -or $hostControl.element.Current.ClassName -cne 'AppControlHost') {
        throw 'Native filename host is not the observed distinct owned picker control.'
    }
    $filename = Find-FileQuayWorkflowElement $Ui '1001' -Within $hostControl
    $pattern = $null
    if ($filename.scope.target_hwnd -ne $hostControl.scope.target_hwnd -or $filename.scope.target_pid -ne $hostControl.scope.target_pid -or
        $filename.element.Current.ClassName -cne 'Edit') {
        throw 'Native filename field is not the observed editable ValuePattern control: identity or class differs.'
    }
    if (-not $filename.element.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern,[ref]$pattern)) {
        throw 'Native filename field is not the observed editable ValuePattern control: unsupported ValuePattern.'
    }
    if ($null -eq $pattern) {
        throw 'Native filename field is not the observed editable ValuePattern control: null pattern returned.'
    }
    if ($pattern.Current.IsReadOnly) {
        throw 'Native filename field is not the observed editable ValuePattern control: read-only pattern.'
    }
    $filename
}

function Open-FileQuayWorkflowExportConfirmation($Ui, $Fixture) {
    Invoke-FileQuayWorkflowAction $Ui (Find-FileQuayWorkflowElement $Ui 'ReceiptExportButton') Invoke
    try {
        $filename = Wait-FileQuayWorkflow {
            Find-FileQuayWorkflowSaveFilename $Ui
        } 'native save picker with a proved owner chain'
    } catch {
        $primary=$_
        try {$Ui.record.save_picker_failure=Get-FileQuayPickerFailureDiagnostic $Ui}
        catch {$Ui.record.save_picker_diagnostic_error=Limit-FileQuayWorkflowDiagnosticText $_.Exception.Message}
        throw $primary
    }
    $picker = @{scope=$filename.scope;element=$filename.scope.root}
    $Ui.record.picker_ownership = @{app_pid=$Ui.application.Id;main_hwnd=$Ui.main_hwnd;picker_pid=$picker.scope.target_pid;picker_hwnd=$picker.scope.target_hwnd;
        owner_chain=[FileQuayQualification.ConsumerInput]::OwnerChain($picker.scope.target_hwnd);process_path=$picker.scope.process.Path}
    Invoke-FileQuayWorkflowAction $Ui $filename Value $Fixture.csv
    $save = Find-FileQuayWorkflowElement $Ui '1' -Within $picker
    Invoke-FileQuayWorkflowAction $Ui $save Invoke
    # The native picker may ask before returning the existing destination.
    $next = Wait-FileQuayWorkflow {
        $custom = @(Find-FileQuayWorkflowElements $Ui 'ReceiptExportConfirmationDialog')
        if ($custom.Count -eq 1) { return @{kind='custom';binding=$custom[0]} }
        $overwrite = @(Find-FileQuayWorkflowElements $Ui '6' -AllowBroker)
        if ($overwrite.Count -eq 1) {
            if ($overwrite[0].element.Current.ControlType -ne [System.Windows.Automation.ControlType]::Button -or
                $overwrite[0].scope.target_hwnd -eq $Ui.main_hwnd) { throw 'Native replacement confirmation is not a distinct owned dialog button.' }
            $dialog = @{scope=$overwrite[0].scope;element=$overwrite[0].scope.root}
            $texts = @(Find-FileQuayWorkflowElements $Ui -Within $dialog -IncludeHidden | ForEach-Object { $_.element.Current.Name })
            if (-not (($texts -join "`n").Contains([IO.Path]::GetFileName($Fixture.csv)))) { throw 'Native replacement dialog does not name the selected CSV.' }
            return @{kind='native';binding=$overwrite[0]}
        }
        $null
    } 'selected-file snapshot and explicit export confirmation'
    $confirmation=$next.binding
    if ($next.kind -eq 'native') {
        Invoke-FileQuayWorkflowAction $Ui $next.binding Invoke
        $confirmation=Wait-FileQuayWorkflow { Find-FileQuayWorkflowElement $Ui 'ReceiptExportConfirmationDialog' } 'app export confirmation after the native decision'
    }
    $null = Wait-FileQuayWorkflow {
        $texts = @(Find-FileQuayWorkflowElements $Ui -Within $confirmation -IncludeHidden | ForEach-Object { $_.element.Current.Name })
        if (-not (($texts -join "`n").Contains($Fixture.csv))) { throw 'Export confirmation does not display the exact selected CSV path.' }
        Find-FileQuayWorkflowElement $Ui 'PrimaryButton' -Within $confirmation
    } 'enabled export confirmation for the exact path'
    Assert-FileQuayWorkflowFile $Fixture.csv $Fixture.previous_csv
    $confirmation
}

function Limit-FileQuayWorkflowDiagnosticText([string]$Text) {
    $Text.Substring(0,[Math]::Min(1024,$Text.Length))
}

function Get-FileQuayWorkflowObservedNode($Element, $Scope, [int]$Depth) {
    $current=$Element.Current
    if ($current.ProcessId -ne $Scope.target_pid) { return }
    $node=[ordered]@{hwnd=$Scope.target_hwnd;process_id=$Scope.target_pid;depth=$Depth;property_errors=[ordered]@{}}
    foreach ($property in ([ordered]@{automation_id='AutomationId';name='Name';class_name='ClassName';control_type='ControlType';
        offscreen='IsOffscreen';enabled='IsEnabled';keyboard_focus='HasKeyboardFocus';keyboard_focusable='IsKeyboardFocusable'}).GetEnumerator()) {
        try {
            $value=$current.($property.Value)
            if ($property.Key -ceq 'control_type') {
                $node.control_type_raw=Limit-FileQuayWorkflowDiagnosticText ([string]$value)
                $value=$value.ProgrammaticName
            }
            if ($value -is [string]) {$value=Limit-FileQuayWorkflowDiagnosticText $value}
            $node[$property.Key]=$value
        } catch {$node.property_errors[$property.Key]=Limit-FileQuayWorkflowDiagnosticText $_.Exception.Message}
    }
    $node
}

function Get-FileQuayWorkflowObservedTree($Scope, $Walker, [ValidateRange(1,160)][int]$MaximumNodes=160, [switch]$IncludePickerProvider) {
    $nodes = [Collections.Generic.List[object]]::new()
    $queue=[Collections.Generic.Queue[object]]::new();$queue.Enqueue(@{element=$Scope.root;depth=0})
    while ($queue.Count -and $nodes.Count -lt $MaximumNodes) {
        $next=$queue.Dequeue()
        try {
            $node=Get-FileQuayWorkflowObservedNode $next.element $Scope $next.depth
            if (-not $node) {continue}
            $nodes.Add($node)
            if ($IncludePickerProvider -and $node.Contains('automation_id') -and $node.Contains('class_name') -and
                (($node.automation_id -ceq '1001' -and $node.class_name -ceq 'Edit') -or
                 ($node.automation_id -ceq 'FileNameControlHost' -and $node.class_name -ceq 'AppControlHost') -or
                 ($node.automation_id -in @('1','2') -and $node.class_name -ceq 'Button'))) {
                try {$node.provider=Get-FileQuayPickerProviderObservation $next.element $Scope}
                catch {$node.provider_error=Limit-FileQuayWorkflowDiagnosticText $_.Exception.Message}
            }
            if ($next.depth -lt 8) {
                try {
                    $child=$Walker.GetFirstChild($next.element)
                    while ($child -and $nodes.Count+$queue.Count -lt $MaximumNodes) {
                        $queue.Enqueue(@{element=$child;depth=$next.depth+1})
                        $child=$Walker.GetNextSibling($child)
                    }
                } catch {$node.children_error=Limit-FileQuayWorkflowDiagnosticText $_.Exception.Message}
            }
        } catch {$nodes.Add(@{depth=$next.depth;observation_error=(Limit-FileQuayWorkflowDiagnosticText $_.Exception.Message)})}
    }
    $nodes.ToArray()
}

function Get-FileQuayWorkflowFailureObservation($Ui) {
    $nodes=[Collections.Generic.List[object]]::new()
    try {
        foreach ($scope in @(Get-FileQuayWorkflowScopes $Ui -AllowBroker)) {
            if ($nodes.Count -ge 160) {return $nodes.ToArray()}
            foreach ($node in @(Get-FileQuayWorkflowObservedTree $scope ([System.Windows.Automation.TreeWalker]::ControlViewWalker) (160-$nodes.Count))) {
                $nodes.Add($node)
            }
        }
    } catch { $nodes.Add(@{observation_error=(Limit-FileQuayWorkflowDiagnosticText $_.Exception.Message)}) }
    $nodes.ToArray()
}

function Add-FileQuayWorkflowClipboardObservation($Ui, [string]$Stage) {
    $observation=[ordered]@{stage=$Stage;at_utc=[DateTimeOffset]::UtcNow.ToString('O');commands=[ordered]@{}}
    try {$observation.clipboard=[FileQuayQualification.ConsumerInput]::ObserveClipboard($Ui.application,$Ui.main_hwnd)}
    catch {$observation.clipboard_error=Limit-FileQuayWorkflowDiagnosticText $_.Exception.Message}
    foreach ($id in @('InnerNavigationToolbarCopyButton','InnerNavigationToolbarCutButton','InnerNavigationToolbarPasteButton','PART_TextBox')) {
        try {
            $bindings=@(Find-FileQuayWorkflowElements $Ui $id -IncludeHidden)
            if ($bindings.Count -gt 8) {throw 'Command observation exceeds its duplicate budget.'}
            $observation.commands[$id]=@(foreach ($binding in $bindings) {
                Get-FileQuayWorkflowObservedNode $binding.element $binding.scope 0
            })
        } catch {$observation.commands[$id]=@{observation_error=(Limit-FileQuayWorkflowDiagnosticText $_.Exception.Message)}}
    }
    Add-FileQuayWorkflowTrace $Ui 'ClipboardObservation' $observation
}

function Invoke-FileQuayConsumerWorkflow($Application, $Window, $Installed, [string]$Work, [System.Collections.IDictionary]$Record, $State) {
    Assert-FileQuayConsumerAdapter $Record.consumer_native_adapter
    $strings=@{}
    [xml]$resources = Get-Content (Join-Path $PSScriptRoot '../../src/Files.App/Strings/en-US/Resources.resw') -Raw
    foreach ($entry in $resources.root.data) { $strings[[string]$entry.name]=[string]$entry.value }
    $workflow = [ordered]@{schema_version=1;passed=$false;trace=[Collections.Generic.List[object]]::new();cleanup_verified=$false;scope='Copy, Move, persisted/UI receipts, CSV destination decision/recovery, metadata clear'}
    $Record.consumer_workflow=$workflow
    $ui=@{application=$Application;main_hwnd=[long]$Window.Current.NativeWindowHandle;brokers=@{};record=$workflow;strings=$strings;evidence=$State.evidence}
    $fixture=$null
    try {
        $fixture=New-FileQuayWorkflowFixture $Work
        $State.fixture=$fixture
        $workflow.fixture_root=$fixture.root; $workflow.initial_files=(Get-FileQuayWorkflowTree $fixture).files
        $history = Join-Path $env:LOCALAPPDATA ('Packages/' + $Installed.PackageFamilyName + '/LocalState/OperationReceipts/v1.json')
        $workflow.history_path=$history; $started=[DateTimeOffset]::UtcNow
        $null=Read-FileQuayWorkflowReceipts $history $fixture 0 $started ([DateTimeOffset]::UtcNow)
        Assert-FileQuayWorkflowFiles $fixture Initial
        Set-FileQuayWorkflowFolder $ui ([IO.Path]::GetDirectoryName($fixture.source))
        Select-FileQuayWorkflowFile $ui $fixture.source
        Add-FileQuayWorkflowClipboardObservation $ui 'before-copy'
        Invoke-FileQuayWorkflowAction $ui (Wait-FileQuayWorkflow { Find-FileQuayWorkflowElement $ui 'InnerNavigationToolbarCopyButton' } 'enabled Copy action') Invoke
        Add-FileQuayWorkflowClipboardObservation $ui 'after-copy-invoke'
        Set-FileQuayWorkflowFolder $ui ([IO.Path]::GetDirectoryName($fixture.copied))
        Add-FileQuayWorkflowClipboardObservation $ui 'copy-destination'
        Invoke-FileQuayWorkflowPaste $ui 'enabled copy Paste action'
        $null=Wait-FileQuayWorkflow { Assert-FileQuayWorkflowFiles $fixture Copied; $true } 'exact copied bytes and protected originals'
        $null=Wait-FileQuayWorkflow { Read-FileQuayWorkflowReceipts $history $fixture 1 $started ([DateTimeOffset]::UtcNow) } 'one persisted successful copy receipt'
        $workflow.copy_files=(Get-FileQuayWorkflowTree $fixture).files
        Select-FileQuayWorkflowFile $ui $fixture.copied
        Add-FileQuayWorkflowClipboardObservation $ui 'before-cut'
        Invoke-FileQuayWorkflowAction $ui (Wait-FileQuayWorkflow { Find-FileQuayWorkflowElement $ui 'InnerNavigationToolbarCutButton' } 'enabled Cut action') Invoke
        Add-FileQuayWorkflowClipboardObservation $ui 'after-cut-invoke'
        Set-FileQuayWorkflowFolder $ui ([IO.Path]::GetDirectoryName($fixture.moved))
        Add-FileQuayWorkflowClipboardObservation $ui 'move-destination'
        Invoke-FileQuayWorkflowPaste $ui 'enabled move Paste action'
        $null=Wait-FileQuayWorkflow { Assert-FileQuayWorkflowFiles $fixture Moved; $true } 'exact moved bytes, removed copy, and protected originals'
        $receipts=@(Wait-FileQuayWorkflow { Read-FileQuayWorkflowReceipts $history $fixture 2 $started ([DateTimeOffset]::UtcNow) } 'two distinct successful persisted receipts')
        $workflow.receipts=$receipts; $workflow.move_files=(Get-FileQuayWorkflowTree $fixture).files
        $list=Open-FileQuayWorkflowHistory $ui
        $workflow.visible_receipts=@(Read-FileQuayWorkflowVisibleReceipts $ui $list $receipts)
        $dialog=Open-FileQuayWorkflowExportConfirmation $ui $fixture
        Invoke-FileQuayWorkflowAction $ui (Find-FileQuayWorkflowElement $ui 'CloseButton' -Within $dialog) Invoke
        $null=Wait-FileQuayWorkflow { if (@(Find-FileQuayWorkflowElements $ui 'ReceiptExportConfirmationDialog').Count -eq 0) { $true } } 'cancelled export confirmation to close'
        Assert-FileQuayWorkflowFiles $fixture Moved
        $workflow.cancelled_export_preserved_previous_bytes=$true
        $null=Open-FileQuayWorkflowHistory $ui
        $dialog=Open-FileQuayWorkflowExportConfirmation $ui $fixture
        Invoke-FileQuayWorkflowAction $ui (Find-FileQuayWorkflowElement $ui 'PrimaryButton' -Within $dialog) Invoke
        $recovery=Wait-FileQuayWorkflow {
            Assert-FileQuayWorkflowCsv $fixture.csv $receipts
            $bar=Find-FileQuayWorkflowElement $ui 'ReceiptStorageErrorBar'
            $texts=@(Find-FileQuayWorkflowElements $ui -Within $bar -IncludeHidden | ForEach-Object { $_.element.Current.Name })
            $text=$texts -join "`n"
            if (-not $text.Contains($strings.ReceiptExportOriginalPreserved)) { throw 'CSV recovery success message is absent.' }
            $paths=@([regex]::Matches($text,[regex]::Escape($fixture.csv)+'\.[0-9a-f]{32}\.filequay-original') | ForEach-Object Value | Select-Object -Unique)
            if ($paths.Count -ne 1) { throw 'CSV recovery path is absent or ambiguous.' }
            Register-FileQuayWorkflowExport $fixture $receipts $paths[0]
            $paths[0]
        } 'CSV rows and displayed preserved-original recovery path'
        $workflow.csv=Get-FileQuayWorkflowFile $fixture.csv; $workflow.csv_recovery=@{path=$recovery;file=(Get-FileQuayWorkflowFile $recovery)}
        Assert-FileQuayWorkflowFiles $fixture Moved
        Invoke-FileQuayWorkflowAction $ui (Find-FileQuayWorkflowElement $ui 'ReceiptClearButton') Invoke
        $clear=Wait-FileQuayWorkflow {
            $matches=@(Find-FileQuayWorkflowElements $ui -Name $strings.ReceiptClear | Where-Object { $_.element.Current.ClassName -ceq 'ContentDialog' })
            if ($matches.Count -ne 1) { throw 'Exact Clear receipts confirmation is absent or ambiguous.' }
            $matches[0]
        } 'clear-metadata confirmation'
        $clearText=@(Find-FileQuayWorkflowElements $ui -Within $clear -IncludeHidden | ForEach-Object { $_.element.Current.Name }) -join "`n"
        if (-not $clearText.Contains($strings.ReceiptClearConfirm)) { throw 'Clear confirmation text differs from the metadata-only contract.' }
        Invoke-FileQuayWorkflowAction $ui (Find-FileQuayWorkflowElement $ui 'PrimaryButton' -Within $clear) Invoke
        $null=Wait-FileQuayWorkflow { $null=Read-FileQuayWorkflowReceipts $history $fixture 0 $started ([DateTimeOffset]::UtcNow); $true } 'persisted empty receipt history'
        $null=Open-FileQuayWorkflowHistory $ui
        $null=Wait-FileQuayWorkflow {
            $empty=Find-FileQuayWorkflowElement $ui -Name $strings.ReceiptEmpty
            if (@(Find-FileQuayWorkflowElements $ui 'ReceiptDetailsExpander').Count -ne 0) { throw 'Receipt cards remain after clearing.' }
            $empty
        } 'visible empty receipt history'
        Assert-FileQuayWorkflowFiles $fixture Moved
        Assert-FileQuayWorkflowCsv $fixture.csv $receipts
        Assert-FileQuayWorkflowFile $recovery $fixture.previous_csv
        $workflow.final_files=(Get-FileQuayWorkflowTree $fixture).files
        $workflow.cleared_history_file=Get-FileQuayWorkflowFile $history
        $workflow.passed=$true
        $Record.consumer_workflow_verified=$true
    } catch {
        $workflow.error=$_.Exception.ToString()
        Add-FileQuayWorkflowClipboardObservation $ui 'failure'
        $workflow.failure_observation=@(Get-FileQuayWorkflowFailureObservation $ui)
        try {$workflow.failure_log_tail=Read-FileQuayWorkflowLogTail (Join-Path $env:LOCALAPPDATA ('Packages/'+$Installed.PackageFamilyName+'/LocalState/debug.log'))}
        catch {$workflow.failure_log_error=$_.Exception.Message}
        throw
    } finally {
        foreach ($process in $ui.brokers.Values) { $process.Dispose() }
    }
}
