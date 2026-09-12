// Copyright 2026 Trieflow LLC. Licensed under the MIT License.
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Windows.Automation;

namespace FileQuayQualification;

public static class UiaProxyRegistration
{
	// WPF's default-proxy stack walk requires a typed first external caller.
	// Keep this frame present before PowerShell's dynamic CallSite frame.
	[MethodImpl(MethodImplOptions.NoInlining)]
	public static void Register(AssemblyName provider)
	{
		ClientSettings.RegisterClientSideProviderAssembly(provider);
	}
}
