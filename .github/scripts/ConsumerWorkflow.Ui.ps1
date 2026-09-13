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

function Get-FileQuayScrollRange($Pattern) {
    $current=$Pattern.Current
    @{vertically_scrollable=$current.VerticallyScrollable;vertical_scroll_percent=$current.VerticalScrollPercent;vertical_view_size=$current.VerticalViewSize;
      horizontally_scrollable=$current.HorizontallyScrollable;horizontal_scroll_percent=$current.HorizontalScrollPercent;horizontal_view_size=$current.HorizontalViewSize}
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
            $pattern=[System.Windows.Automation.ScrollPattern]$element.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern)
            $attempt=@{action=$Action;outcome='not-sent';before=(Get-FileQuayScrollRange $pattern);after=$null;after_error=$null}
            Add-FileQuayWorkflowTrace $Ui 'ReceiptScrollAttempt' $attempt
            $attempt.target_state_before_send=Get-FileQuayWorkflowTargetState $Ui $Binding
            Assert-FileQuayWorkflowTarget $scope $attempt.target_state_before_send
            try {
                if (-not $attempt.before.vertically_scrollable) {
                    $attempt.outcome='not-sent-not-scrollable'
                    return
                }
                $pattern.Scroll([System.Windows.Automation.ScrollAmount]::NoAmount,$direction)
                $attempt.outcome='completed'
            } catch {
                $attempt.outcome='failed';$attempt.error=$_.Exception.ToString()
                # Mark only a typed failure thrown by the actual Scroll call.
                # Ownership, discovery, and range-read failures are never marked.
                $cause=$_.Exception
                for ($depth=0; $cause -and $depth -lt 8; $depth++) {
                    if ($cause -is [InvalidOperationException]) {$cause.Data['FileQuay.ScrollCall']=$true;break}
                    $cause=$cause.InnerException
                }
                throw
            } finally {
                try {$attempt.after=Get-FileQuayScrollRange $pattern}
                catch {$attempt.after_error=Limit-FileQuayWorkflowDiagnosticText $_.Exception.ToString()}
            }
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

function Get-FileQuayReceiptLayoutFields($Current, [switch]$Range) {
    $result=[ordered]@{property_errors=[ordered]@{}}
    $fields=if($Range){[ordered]@{vertical_scroll_percent='VerticalScrollPercent';vertical_view_size='VerticalViewSize';
        horizontally_scrollable='HorizontallyScrollable';horizontal_scroll_percent='HorizontalScrollPercent';horizontal_view_size='HorizontalViewSize'}}
    else {[ordered]@{process_id='ProcessId';automation_id='AutomationId';name='Name';class_name='ClassName';
        control_native_hwnd='NativeWindowHandle';enabled='IsEnabled'}}
    foreach($field in $fields.GetEnumerator()) {
        try {
            $value=$Current.($field.Value)
            if($value -is [string]){$value=Limit-FileQuayWorkflowDiagnosticText $value}
            $result[$field.Key]=$value
        } catch {$result.property_errors[$field.Key]=Limit-FileQuayWorkflowDiagnosticText $_.Exception.Message}
    }
    $result
}

function Show-FileQuayWorkflowElement($Ui, [string]$Name,
    [ValidateSet('ReceiptDetailsExpander','ReceiptSourcePaths','ReceiptDestinationPaths')][string]$Part='ReceiptDetailsExpander',
    [ValidateRange(0.01,30)][double]$MaximumSeconds=30) {
    $lastUnavailable=$null;$failedScroll=$null;$failedScope=$null
    $deadline=[Diagnostics.Stopwatch]::StartNew()
    for ($attempt=0; $attempt -lt 16 -and $deadline.Elapsed.TotalSeconds -lt $MaximumSeconds; $attempt++) {
        try {
            if ($failedScroll) {
                $currentList=Find-FileQuayWorkflowElement $Ui 'ReceiptHistoryList'
                $listState=Get-FileQuayWorkflowTargetState $Ui $currentList
                Add-FileQuayWorkflowTrace $Ui 'ReceiptScrollTargetObservation' @{part='list';name=$Name;expected_hwnd=$failedScope.target_hwnd;expected_pid=$failedScope.target_pid;state=$listState}
                Assert-FileQuayWorkflowTarget $failedScope $listState
            }
            # ListView templates can replace both cards and their scroll provider.
            # Reobserve the exact owned card/detail before every scrolling attempt.
            $binding=Find-FileQuayWorkflowReceiptElement $Ui $Name $Part
            $detailReadStarted=[DateTimeOffset]::UtcNow.ToString('O');$detailReadElapsed=$deadline.ElapsedMilliseconds
            $detailCurrent=$binding.element.Current
            $detailOffscreen=$detailCurrent.IsOffscreen
            $detailReadEnded=[DateTimeOffset]::UtcNow.ToString('O')
            if (-not $detailOffscreen) {
                if ($failedScroll) {
                    $visibleState=Get-FileQuayWorkflowTargetState $Ui $binding
                    Add-FileQuayWorkflowTrace $Ui 'ReceiptScrollTargetObservation' @{part=$Part;name=$Name;expected_hwnd=$failedScope.target_hwnd;expected_pid=$failedScope.target_pid;state=$visibleState}
                    Assert-FileQuayWorkflowTarget $failedScope $visibleState
                    Add-FileQuayWorkflowTrace $Ui 'ReceiptScrollVisibilityRequery' @{name=$Name;automation_id=$Part;attempt=($attempt+1);visible=$true;input_sent=$false;state=$visibleState}
                }
                if ($deadline.Elapsed.TotalSeconds -ge $MaximumSeconds) {break}
                return $binding
            }
            if ($failedScroll) {
                Add-FileQuayWorkflowTrace $Ui 'ReceiptScrollVisibilityRequery' @{name=$Name;automation_id=$Part;attempt=($attempt+1);visible=$false;input_sent=$false}
                Start-Sleep -Milliseconds 100
                continue
            }
            $layout=[ordered]@{name=$Name;automation_id=$Part;attempt=($attempt+1);
                expected_hwnd=$binding.scope.target_hwnd;expected_pid=$binding.scope.target_pid;
                read_started_utc=$detailReadStarted;elapsed_ms=$detailReadElapsed;
                detail=(Get-FileQuayReceiptLayoutFields $detailCurrent);ancestors=[Collections.Generic.List[object]]::new();reason='read-error'}
            $layout.detail.offscreen=$detailOffscreen
            $layout.detail.predicate_read_ended_utc=$detailReadEnded
            $container=$null
            try {
                $ancestor=[System.Windows.Automation.TreeWalker]::RawViewWalker.GetParent($binding.element)
                for ($i=0; $ancestor -and $i -lt 24; $i++) {
                    $node=[ordered]@{index=$i;read_started_utc=[DateTimeOffset]::UtcNow.ToString('O');
                        elapsed_ms=$deadline.ElapsedMilliseconds;reason='read-error'}
                    $layout.ancestors.Add($node)
                    try {
                        $node.reason='read-native-window'
                        $nativeWindow=Get-FileQuayWorkflowElementWindow $ancestor
                        $node.native_window=$nativeWindow
                        if ($nativeWindow -ne $binding.scope.target_hwnd) {
                            $node.reason='native-window-mismatch';$layout.reason=$node.reason
                            # No additional provider queries after this ownership refusal.
                            break
                        }
                        $node.reason='read-current'
                        $current=$ancestor.Current
                        $offscreen=$current.IsOffscreen
                        foreach($entry in (Get-FileQuayReceiptLayoutFields $current).GetEnumerator()){$node[$entry.Key]=$entry.Value}
                        $node.offscreen=$offscreen;$scroll=$null;$node.reason='offscreen'
                        if (-not $offscreen) {
                            $node.reason='read-scroll-pattern'
                            $hasPattern=$ancestor.TryGetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern,[ref]$scroll)
                            $node.scroll_pattern=$hasPattern;$node.reason='no-scroll-pattern'
                            if($hasPattern) {
                                $node.reason='read-scroll-range'
                                $range=$scroll.Current;$scrollable=$range.VerticallyScrollable
                                $node.scroll=Get-FileQuayReceiptLayoutFields $range -Range
                                $node.scroll.vertically_scrollable=$scrollable;$node.reason='not-scrollable'
                                if($scrollable){$container=@{scope=$binding.scope;element=$ancestor};$node.reason='selected';break}
                            }
                        }
                        $ancestor=[System.Windows.Automation.TreeWalker]::RawViewWalker.GetParent($ancestor)
                    } finally {$node.read_ended_utc=[DateTimeOffset]::UtcNow.ToString('O')}
                }
                if($container){$layout.reason='selected'}
                elseif($layout.reason -ne 'native-window-mismatch'){$layout.reason=if($ancestor){'ancestor-limit'}else{'ancestor-end'}}
            } finally {
                $layout.read_ended_utc=[DateTimeOffset]::UtcNow.ToString('O')
                $layout.elapsed_end_ms=$deadline.ElapsedMilliseconds
                if(-not $container) {
                    # Preserve the original refusal/provider exception if the
                    # bounded metadata sink itself is unavailable.
                    try {Add-FileQuayWorkflowTrace $Ui 'ReceiptScrollContainerRefusal' $layout} catch {}
                }
            }
            if (-not $container) { throw 'Offscreen receipt detail has no visible owned scroll container.' }
            $direction=if ($binding.element.Current.BoundingRectangle.Top -lt $container.element.Current.BoundingRectangle.Top) {'ScrollUp'} else {'ScrollDown'}
            $failedScope=$container.scope
            Invoke-FileQuayWorkflowAction $Ui $container $direction
        } catch {
            $errorType=$_.Exception;$unavailable=$null;$invalidScroll=$null
            for ($depth=0; $errorType -and $depth -lt 8; $depth++) {
                if ($errorType -is [System.Windows.Automation.ElementNotAvailableException]) { $unavailable=$errorType;break }
                if ($errorType -is [InvalidOperationException] -and $errorType.Data['FileQuay.ScrollCall'] -eq $true) {$invalidScroll=$errorType;break}
                $errorType=$errorType.InnerException
            }
            if ($invalidScroll) {
                $failedScroll=$_.Exception
                Add-FileQuayWorkflowTrace $Ui 'ReceiptScrollVisibilityRequery' @{name=$Name;automation_id=$Part;attempt=($attempt+1);error_type=$invalidScroll.GetType().FullName;input_sent=$false}
            } elseif ($unavailable) {
                $lastUnavailable=$unavailable
                Add-FileQuayWorkflowTrace $Ui 'ReceiptScrollRequery' @{name=$Name;automation_id=$Part;attempt=($attempt+1);error_type=$unavailable.GetType().FullName}
            } elseif ($failedScroll) {
                throw [InvalidOperationException]::new(('Receipt visibility/ownership observation failed after Scroll: '+$_.Exception.Message),$failedScroll)
            } else {throw}
        }
        Start-Sleep -Milliseconds 100
    }
    $cause=if($failedScroll){$failedScroll}else{$lastUnavailable}
    throw [InvalidOperationException]::new('The receipt detail did not become visible within the scroll budget.', $cause)
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

function Assert-FileQuayWorkflowTaskReplacement($Ui, $Binding) {
    if (-not $Binding.ContainsKey('task_replacement')) { throw 'Task replacement has no retained picker context.' }
    $context=$Binding.task_replacement;$scope=$Binding.scope;$root=$scope.root.Current
    if ($scope.target_pid -ne $context.picker.scope.target_pid -or $scope.process.Id -ne $context.picker.scope.process.Id -or
        $scope.target_hwnd -in @($Ui.main_hwnd,$context.picker.scope.target_hwnd) -or
        $root.NativeWindowHandle -ne $scope.target_hwnd -or $root.ProcessId -ne $scope.target_pid -or
        $root.Name -cne 'Confirm Save As' -or $root.ClassName -cne '#32770' -or
        $root.ControlType -ne [System.Windows.Automation.ControlType]::Window -or $root.IsOffscreen -or -not $root.IsEnabled -or
        -not $Ui.record.picker_filename.verified -or $Ui.record.picker_filename.expected -cne $context.path -or
        $Ui.record.picker_filename.value -cne $context.path) { throw 'Task replacement dialog or exact selected filename changed.' }
    Assert-FileQuayWorkflowTarget $scope (Get-FileQuayWorkflowTargetState $Ui $Binding)
    $dialog=@{scope=$scope;element=$scope.root}
    $yes=@(Find-FileQuayWorkflowElements $Ui 'CommandButton_6' -Within $dialog)
    if ($yes.Count -ne 1) { throw 'Task replacement Yes identity is absent or ambiguous.' }
    $expectedRuntime=@($Binding.element.GetRuntimeId());$observedRuntime=@($yes[0].element.GetRuntimeId())
    if ($expectedRuntime.Count -lt 1 -or $expectedRuntime.Count -gt 64 -or $observedRuntime.Count -lt 1 -or
        $observedRuntime.Count -gt 64 -or [string]::Join(',',[int[]]$observedRuntime) -cne
        [string]::Join(',',[int[]]$expectedRuntime)) { throw 'Task replacement Yes identity is absent or ambiguous.' }
    foreach($part in @(@('ContentText','Element',[System.Windows.Automation.ControlType]::Text,
                        ([IO.Path]::GetFileName($context.path)+" already exists.`r`nDo you want to replace it?")),
                      @('CommandButton_7','CCPushButton',[System.Windows.Automation.ControlType]::Button,'No'))){
        $found=@(Find-FileQuayWorkflowElements $Ui $part[0] -Within $dialog)
        if($found.Count -ne 1){throw 'Task replacement content or No sibling is absent or ambiguous.'}
        $node=$found[0].element.Current
        if($node.AutomationId -cne $part[0] -or $node.ClassName -cne $part[1] -or $node.ControlType -ne $part[2] -or
           $node.Name -cne $part[3] -or $node.ProcessId -ne $scope.target_pid -or $node.IsOffscreen -or -not $node.IsEnabled -or
           ($part[0] -ceq 'CommandButton_7' -and -not $node.IsKeyboardFocusable)){
            throw 'Task replacement content or No sibling differs from the observed dialog.'
        }
        Assert-FileQuayWorkflowTarget $scope (Get-FileQuayWorkflowTargetState $Ui $found[0])
    }
}

function Find-FileQuayWorkflowReplacement($Ui, $Picker, [string]$Path) {
    $classic=@(Find-FileQuayWorkflowElements $Ui '6' -AllowBroker)
    $task=@(Find-FileQuayWorkflowElements $Ui 'CommandButton_6' -AllowBroker)
    if($classic.Count+$task.Count -gt 1){throw 'Native replacement confirmation is ambiguous.'}
    if($classic.Count -eq 1){
        $button=$classic[0]
        if($button.element.Current.ControlType -ne [System.Windows.Automation.ControlType]::Button -or
           $button.scope.target_hwnd -eq $Ui.main_hwnd){throw 'Native replacement confirmation is not a distinct owned dialog button.'}
        $dialog=@{scope=$button.scope;element=$button.scope.root}
        $texts=@(Find-FileQuayWorkflowElements $Ui -Within $dialog -IncludeHidden|ForEach-Object {$_.element.Current.Name})
        if(-not (($texts -join "`n").Contains([IO.Path]::GetFileName($Path)))){throw 'Native replacement dialog does not name the selected CSV.'}
        return @{kind='native';binding=$button;id='6'}
    }
    if($task.Count -eq 1){
        $button=$task[0];$button.task_replacement=@{picker=$Picker;path=$Path}
        Assert-FileQuayWorkflowTaskReplacement $Ui $button
        $Ui.record.native_replacement=@{route='observed-task-dialog';picker_pid=$Picker.scope.target_pid;
            picker_hwnd=$Picker.scope.target_hwnd;dialog_pid=$button.scope.target_pid;dialog_hwnd=$button.scope.target_hwnd;
            owner_chain=[FileQuayQualification.ConsumerInput]::OwnerChain($button.scope.target_hwnd);
            selected_path=$Path;dialog_title='Confirm Save As';dialog_class='#32770';
            scope_hwnd_is_not_control_native_hwnd=$true;button=(Get-FileQuayWorkflowObservedNode $button.element $button.scope 0);
            provider=$null;provider_error=$null}
        try{$Ui.record.native_replacement.provider=Get-FileQuayPickerProviderObservation $button.element $button.scope}
        catch{$Ui.record.native_replacement.provider_error=Limit-FileQuayWorkflowDiagnosticText $_.Exception.Message}
        return @{kind='native';binding=$button;id='CommandButton_6'}
    }
}

function Assert-FileQuayWorkflowPickerButton($Ui, $Binding, [string]$Id, [string]$Name, [long]$ExpectedHandle=0, [switch]$Focused) {
    $task=$Id -ceq 'CommandButton_6' -and $Name -ceq 'Yes'
    if($task){Assert-FileQuayWorkflowTaskReplacement $Ui $Binding}
    $class=if($task){'CCPushButton'}else{'Button'}
    $current=$Binding.element.Current
    if ((($Id -cne '1' -or $Name -cne 'Save') -and ($Id -cne '6' -or $Name -cne 'Yes') -and -not $task) -or
        $Binding.scope.target_hwnd -eq $Ui.main_hwnd -or $current.ProcessId -ne $Binding.scope.target_pid -or
        $current.AutomationId -cne $Id -or $current.Name -cne $Name -or $current.ClassName -cne $class -or
        $current.ControlType -ne [System.Windows.Automation.ControlType]::Button -or
        $current.IsOffscreen -or -not $current.IsEnabled -or -not $current.IsKeyboardFocusable -or
        -not $current.NativeWindowHandle -or ($task -and $current.NativeWindowHandle -eq $Binding.scope.target_hwnd) -or
        ($ExpectedHandle -and $current.NativeWindowHandle -ne $ExpectedHandle) -or
        ($Focused -and -not $current.HasKeyboardFocus)) {
        # Retain which original provider property failed; the old generic error
        # concealed whether the native HWND, identity, or focus was unavailable.
        Add-FileQuayWorkflowTrace $Ui 'NativeButtonRefused' @{
            expected_id=$Id;expected_name=$Name;expected_hwnd=$ExpectedHandle;focus_required=[bool]$Focused
            automation_id=([string]$current.AutomationId).Substring(0,[Math]::Min(64,([string]$current.AutomationId).Length))
            name=([string]$current.Name).Substring(0,[Math]::Min(64,([string]$current.Name).Length))
            class_name=([string]$current.ClassName).Substring(0,[Math]::Min(128,([string]$current.ClassName).Length))
            is_button=($current.ControlType -eq [System.Windows.Automation.ControlType]::Button)
            button_hwnd=[long]$current.NativeWindowHandle;process_id=$current.ProcessId;picker_hwnd=$Binding.scope.target_hwnd
            picker_pid=$Binding.scope.target_pid;offscreen=$current.IsOffscreen;enabled=$current.IsEnabled
            keyboard_focusable=$current.IsKeyboardFocusable;keyboard_focus=$current.HasKeyboardFocus
        }
        throw 'The exact owned native picker button identity or focus changed.'
    }
    [long]$current.NativeWindowHandle
}

function Invoke-FileQuayWorkflowPickerButton($Ui, $Binding, [string]$Id, [string]$Name) {
    $handle=Assert-FileQuayWorkflowPickerButton $Ui $Binding $Id $Name
    $scope=$Binding.scope
    [FileQuayQualification.ConsumerInput]::Foreground($Ui.application,$Ui.main_hwnd,$scope.process,$scope.target_hwnd)
    Assert-FileQuayWorkflowTarget $scope (Get-FileQuayWorkflowTargetState $Ui $Binding)
    $Binding.element.SetFocus()
    # Observe the single focus request completing. Identity/ownership failures
    # remain immediate; no focus request or input is retried during this wait.
    $focusReads=[Collections.Generic.List[object]]::new()
    for($attempt=0;$attempt -lt 20;$attempt++) {
        $state=Get-FileQuayWorkflowTargetState $Ui $Binding
        $null=Assert-FileQuayWorkflowPickerButton $Ui $Binding $Id $Name $handle
        Assert-FileQuayWorkflowTarget $scope $state
        $focused=[bool]$Binding.element.Current.HasKeyboardFocus
        $focusReads.Add(@{at_utc=[DateTimeOffset]::UtcNow.ToString('O');focused=$focused})
        if($focused){break}
        if($attempt -lt 19){Start-Sleep -Milliseconds 50}
    }
    Add-FileQuayWorkflowTrace $Ui 'NativeButtonFocusObservation' @{automation_id=$Id;button_hwnd=$handle;observations=$focusReads.ToArray()}
    $null=Assert-FileQuayWorkflowPickerButton $Ui $Binding $Id $Name $handle -Focused
    Assert-FileQuayWorkflowTarget $scope (Get-FileQuayWorkflowTargetState $Ui $Binding)
    Add-FileQuayWorkflowTrace $Ui 'NativeButtonSpace' @{automation_id=$Id;name=$Name;button_hwnd=$handle;state=$state}
    # The Microsoft standard-button Invoke provider sends synchronous BM_CLICK.
    # Send ordinary Space once; the compiled adapter rechecks this exact native
    # control's focus/ownership immediately before its only SendInput boundary.
    [FileQuayQualification.ConsumerInput]::FocusedSpace($Ui.application,$Ui.main_hwnd,$scope.process,$scope.target_hwnd,$handle)
}

function Assert-FileQuayWorkflowFilenameControl($Ui, $Filename, [long]$ExpectedHandle=0, [switch]$Focused) {
    $current=$Filename.element.Current
    if ($Filename.scope.target_hwnd -eq $Ui.main_hwnd -or $current.ProcessId -ne $Filename.scope.target_pid -or
        $current.AutomationId -cne '1001' -or $current.ClassName -cne 'Edit' -or
        $current.ControlType -ne [System.Windows.Automation.ControlType]::Edit -or
        -not $current.NativeWindowHandle -or ($ExpectedHandle -and $current.NativeWindowHandle -ne $ExpectedHandle) -or
        $current.IsOffscreen -or -not $current.IsEnabled -or -not $current.IsKeyboardFocusable -or
        ($Focused -and -not $current.HasKeyboardFocus)) {
        throw 'The exact owned native filename control identity or focus changed.'
    }
    [long]$current.NativeWindowHandle
}

function Set-FileQuayWorkflowPickerFilename($Ui, $Filename, [string]$Text) {
    $handle=Assert-FileQuayWorkflowFilenameControl $Ui $Filename
    $scope=$Filename.scope
    Assert-FileQuayWorkflowTarget $scope (Get-FileQuayWorkflowTargetState $Ui $Filename)
    $pattern=[System.Windows.Automation.ValuePattern]$Filename.element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
    if ($pattern.Current.IsReadOnly) {throw 'Native filename is read-only before input.'}
    [FileQuayQualification.ConsumerInput]::Foreground($Ui.application,$Ui.main_hwnd,$scope.process,$scope.target_hwnd)
    $Filename.element.SetFocus()
    $observations=[Collections.Generic.List[object]]::new()
    for($attempt=0;$attempt -lt 20;$attempt++) {
        $state=Get-FileQuayWorkflowTargetState $Ui $Filename
        $null=Assert-FileQuayWorkflowFilenameControl $Ui $Filename $handle
        Assert-FileQuayWorkflowTarget $scope $state
        $focused=[bool]$Filename.element.Current.HasKeyboardFocus
        $observations.Add(@{at_utc=[DateTimeOffset]::UtcNow.ToString('O');focused=$focused})
        if($focused){break}
        if($attempt -lt 19){Start-Sleep -Milliseconds 50}
    }
    Add-FileQuayWorkflowTrace $Ui 'NativeFilenameFocusObservation' @{edit_hwnd=$handle;observations=$observations.ToArray()}
    $null=Assert-FileQuayWorkflowFilenameControl $Ui $Filename $handle -Focused
    Assert-FileQuayWorkflowTarget $scope (Get-FileQuayWorkflowTargetState $Ui $Filename)
    Add-FileQuayWorkflowTrace $Ui 'NativeFilenameText' @{edit_hwnd=$handle;characters=$Text.Length;state=$state}
    # Actual run34703681708 retained correct WM_SETTEXT readback but the picker
    # returned its default path. Deliver one focused keyboard replacement; keep
    # both exact text readback and the app's returned-path confirmation checks.
    [FileQuayQualification.ConsumerInput]::FocusedText($Ui.application,$Ui.main_hwnd,$scope.process,$scope.target_hwnd,$handle,$Text)
}

function Confirm-FileQuayWorkflowPickerFilename($Ui, $Filename, [string]$Expected) {
    $handle=Assert-FileQuayWorkflowFilenameControl $Ui $Filename
    $observations=[Collections.Generic.List[object]]::new()
    $Ui.record.picker_filename=@{expected=$Expected;value='';read_only=$false;value_truncated=$false;verified=$false;
        picker_hwnd=$Filename.scope.target_hwnd;picker_pid=$Filename.scope.target_pid;observations=$observations}
    for($attempt=0;$attempt -lt 20;$attempt++) {
        Assert-FileQuayWorkflowTarget $Filename.scope (Get-FileQuayWorkflowTargetState $Ui $Filename)
        $null=Assert-FileQuayWorkflowFilenameControl $Ui $Filename $handle
        $pattern=[System.Windows.Automation.ValuePattern]$Filename.element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        $value=$pattern.Current
        $text=[string]$value.Value;$readOnly=[bool]$value.IsReadOnly
        $Ui.record.picker_filename.value=Limit-FileQuayWorkflowDiagnosticText $text
        $Ui.record.picker_filename.read_only=$readOnly;$Ui.record.picker_filename.value_truncated=($text.Length -gt 1024)
        $observations.Add(@{at_utc=[DateTimeOffset]::UtcNow.ToString('O');value=$Ui.record.picker_filename.value;read_only=$readOnly;value_truncated=($text.Length -gt 1024)})
        if($readOnly){throw 'Native filename became read-only after input.'}
        if($text -ceq $Expected){break}
        if($attempt -lt 19){Start-Sleep -Milliseconds 50}
    }
    if ($text -cne $Expected) { throw 'Native filename does not retain the exact selected CSV path.' }
    Assert-FileQuayWorkflowTarget $Filename.scope (Get-FileQuayWorkflowTargetState $Ui $Filename)
    $Ui.record.picker_filename.verified=$true
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
    Set-FileQuayWorkflowPickerFilename $Ui $filename $Fixture.csv
    Confirm-FileQuayWorkflowPickerFilename $Ui $filename $Fixture.csv
    $save = Find-FileQuayWorkflowElement $Ui '1' -Within $picker
    Invoke-FileQuayWorkflowPickerButton $Ui $save '1' 'Save'
    # The native picker may ask before returning the existing destination.
    $next = Wait-FileQuayWorkflow {
        $custom = @(Find-FileQuayWorkflowElements $Ui 'ReceiptExportConfirmationDialog')
        if ($custom.Count -eq 1) { return @{kind='custom';binding=$custom[0]} }
        Find-FileQuayWorkflowReplacement $Ui $picker $Fixture.csv
    } 'selected-file snapshot and explicit export confirmation'
    $confirmation=$next.binding
    if ($next.kind -eq 'native') {
        Assert-FileQuayWorkflowFile $Fixture.csv $Fixture.previous_csv
        Invoke-FileQuayWorkflowPickerButton $Ui $next.binding $next.id 'Yes'
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
        $null=Wait-FileQuayWorkflow { if (@(Find-FileQuayWorkflowElements $ui 'ReceiptExportConfirmationDialog').Count -eq 0) { $true } } 'confirmed export dialog to close'
        $null=Open-FileQuayWorkflowHistory $ui
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
            # WinUI exposes this ContentDialog as the observed Popup Window peer.
            $matches=@(Find-FileQuayWorkflowElements $ui -Name $strings.ReceiptClear | Where-Object {
                $_.element.Current.ClassName -ceq 'Popup' -and $_.element.Current.ControlType -eq [System.Windows.Automation.ControlType]::Window })
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
        # Retain the already verified, exclusively owned fictional output so the
        # separate Store export can repeat the CSV oracle after fixture cleanup.
        $workflow.csv_bytes_base64=[Convert]::ToBase64String([IO.File]::ReadAllBytes($fixture.csv))
        $workflow.cleared_history=[IO.File]::ReadAllText($history) | ConvertFrom-Json -AsHashtable
        $workflow.passed=$true
        $Record.consumer_workflow_verified=$true
    } catch {
        $workflow.error=$_.Exception.ToString()
        if ($_.Exception.Data.Contains('FileQuayWorkflowTargetRefusal')) {$workflow.target_refusal=$_.Exception.Data['FileQuayWorkflowTargetRefusal']}
        Add-FileQuayWorkflowClipboardObservation $ui 'failure'
        $workflow.failure_observation=@(Get-FileQuayWorkflowFailureObservation $ui)
        try {$workflow.failure_log_tail=Read-FileQuayWorkflowLogTail (Join-Path $env:LOCALAPPDATA ('Packages/'+$Installed.PackageFamilyName+'/LocalState/debug.log'))}
        catch {$workflow.failure_log_error=$_.Exception.Message}
        throw
    } finally {
        foreach ($process in $ui.brokers.Values) { $process.Dispose() }
    }
}
