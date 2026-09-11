// Copyright (c) Trieflow LLC. Licensed under the MIT License.
using System;
namespace Files.App.Utils.StatusCenter.Receipts;

public sealed class ObservedOperationProgress<T>(Action<T> observe, Action<T> display) : Progress<T>(display)
{
	protected override void OnReport(T value)
	{
		// Inspect mutable reports before Progress<T> posts them to the UI synchronization context.
		observe(value);
		base.OnReport(value);
	}
}
