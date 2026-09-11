// Copyright(c) Files Community
// Licensed under the MIT License.
// FileQuay modifications copyright 2026 Trieflow LLC.
namespace Files.App.Helpers
{
	public static class LocationHelpers
	{
		// EXIF coordinates stay on the device; automatic remote reverse-geocoding is disabled.
		public static Task<string?> GetAddressFromCoordinatesAsync(double? Lat, double? Lon) => Task.FromResult<string?>(null);
	}
}
