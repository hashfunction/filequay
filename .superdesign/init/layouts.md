# Status Center flyout
Native flyout in NavigationToolbar.xaml, 400 logical pixels wide and 500 maximum height.

```xml
				<Button.Flyout>
					<Flyout
						contract8Present:ShouldConstrainToRootBounds="False"
						AutomationProperties.Name="{helpers:ResourceString Name=StatusCenter}"
						Opened="{x:Bind OngoingTasksViewModel.OnStatusCenterFlyoutOpened, Mode=OneWay}"
						Placement="BottomEdgeAlignedRight">
						<Flyout.FlyoutPresenterStyle>
							<Style TargetType="FlyoutPresenter">
								<Setter Property="Padding" Value="0" />
								<Setter Property="CornerRadius" Value="{StaticResource OverlayCornerRadius}" />
							</Style>
						</Flyout.FlyoutPresenterStyle>

						<ucs:StatusCenter
							x:Name="OngoingTasksControl"
							Width="400"
							MinHeight="120"
							MaxHeight="500"
							x:FieldModifier="public"
							IsTabStop="True" />
					</Flyout>
				</Button.Flyout>

```
